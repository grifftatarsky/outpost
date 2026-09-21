import CarpenterKit
import CryptoKit
import Foundation

// MARK: Who can be reached, and the room keys they are owed

extension AppSession {
    func peers() -> [Peer] {
        guard let enrolment else { return [] }
        let reachable = notShutOut(addressable())

        return replica.knownParticipants
            .filter { $0 != enrolment.identity.id && reachable.contains($0) }
            .compactMap { participant -> Peer? in
                guard let secret = pairwiseSecret(with: participant) else { return nil }
                return Peer(secret: secret, them: participant, me: enrolment.identity.id)
            }
    }

    private func addressable() -> Set<ParticipantID> {
        guard let me = enrolment?.identity.id else { return [] }
        let projected = projection

        var reachable: Set<ParticipantID> = []
        for summary in projected.summaries() {
            let roster = roster(of: summary.id)
            reachable.formUnion(roster.members)
            reachable.formUnion(roster.requests.keys)
            reachable.formUnion(roster.absent)
        }
        reachable.formUnion(outpostAccess.audience(at: clock.now))
        reachable.formUnion(projected.outpostAuthors().map(\.id))
        for repair in persisted.repairs { reachable.formUnion(repair.asked) }
        for duty in persisted.repairDuties { reachable.insert(duty.from) }
        for invitation in invitationsOutsideTheirRoom() {
            reachable.insert(invitation.attestation.inviter)
        }
        reachable.remove(me)
        return reachable
    }

    func peersToRingForWall(carrying sending: [Entry]) -> [Peer] {
        let posts = Set(sending.filter(\.isOnOwnOutpost).map(\.hash))
        let carryingOwnPost = !posts.isDisjoint(with: unsentWallPosts)
        guard carryingOwnPost || !wallsWrittenOn.isEmpty else { return [] }

        let readers = outpostReaders()
        return peers().filter {
            if wallsWrittenOn.contains($0.them) { return true }
            return carryingOwnPost && readers.contains($0.them)
                && persisted.wantsOutpostBell.contains($0.them)
        }
    }

    func mayReceive(_ entry: Entry, among everyone: [Peer]) -> [Peer] {
        guard let me = enrolment?.identity.id else { return [] }
        switch entry.conversation {
        case .outpost(let owner):
            return outpostAudience(of: entry, owner: owner, me: me, among: everyone)
        case .room, .solo:
            return roomAudience(of: entry, among: everyone)
        }
    }

    private func outpostAudience(
        of entry: Entry, owner: ParticipantID, me: ParticipantID, among everyone: [Peer]
    ) -> [Peer] {
        guard owner == me else {
            guard entry.author != owner else { return [] }
            return everyone.filter { $0.them == owner }
        }
        let opened = entryOpener()(entry)
        if entry.payload.alsoFor != nil {
            guard let named = wallOwnerAddressed(by: opened) else { return [] }
            return everyone.filter { $0.them == named }
        }
        let readers = outpostReaders()
        let subject =
            opened?.type == .outpostAccess
            ? (try? opened?.decode(OutpostAccessBody.self))?.person : nil
        return everyone.filter {
            readers.contains($0.them) || $0.them == entry.author || $0.them == subject
        }
    }

    private func roomAudience(of entry: Entry, among everyone: [Peer]) -> [Peer] {
        let room = entry.conversation
        let roster = roster(of: room)
        if roster.members.isEmpty, roster.founder == nil {
            let letMeIn = Set(
                persisted.acceptedInvitations
                    .filter { $0.attestation.room == room }
                    .map(\.attestation.inviter))
            return everyone.filter { letMeIn.contains($0.them) }
        }
        let floors = roster.everyHistoryFloor
        func lastEpoch(_ hash: EntryHash?) -> EpochNumber? {
            hash.flatMap { replica.entry(named: $0) }?.payload.epoch
        }
        return everyone.filter { peer in
            if let removal = roster.removals[peer.them] {
                guard let last = lastEpoch(removal.entry) else { return false }
                return entry.payload.epoch <= last
            }
            if let departure = roster.departures[peer.them] {
                guard let last = lastEpoch(departure.entry) else { return false }
                return entry.payload.epoch <= last
            }
            guard roster.members.contains(peer.them) || roster.founder == peer.them
                || roster.requests.keys.contains(peer.them)
            else { return false }
            if let floor = floors[peer.them] { return entry.payload.epoch >= floor }
            if let invitation = roster.invitation(of: peer.them), !invitation.sharesHistory {
                return false
            }
            return true
        }
    }

    func wallOwnerAddressed(by payload: Payload?) -> ParticipantID? {
        guard let payload else { return nil }
        let open = entryOpener()
        var target: EntryHash?
        switch payload.type {
        case .comment: target = (try? payload.decode(CommentBody.self))?.target
        case .reaction: target = (try? payload.decode(ReactionBody.self))?.target
        default: return nil
        }
        var walked = 0
        while let hash = target, walked < 8 {
            walked += 1
            guard let found = replica.entry(named: hash) else { return nil }
            guard let opened = open(found) else { return found.author }
            switch opened.type {
            case .comment: target = (try? opened.decode(CommentBody.self))?.target
            case .reaction: target = (try? opened.decode(ReactionBody.self))?.target
            default: return found.author
            }
        }
        return nil
    }

    func peopleTheyMayKnowOf(_ entries: [Entry], among audience: [Peer]) -> Set<ParticipantID> {
        var who = Set(entries.map(\.author))
        who.formUnion(audience.map(\.them))
        if let me = enrolment?.identity.id { who.insert(me) }
        for room in Set(entries.filter { !$0.isOnOwnOutpost }.map(\.conversation)) {
            let roster = roster(of: room)
            who.formUnion(roster.members)
            who.formUnion(roster.requests.keys)
            who.formUnion(roster.absent)
        }
        return who
    }

    func withheldFromEveryone() -> [ParticipantID: [FeedGap]] {
        if let cachedWithheld { return cachedWithheld }
        let everyone = peers()
        guard !everyone.isEmpty else { return [:] }
        var out: [ParticipantID: [FeedGap]] = [:]
        for entry in replica.allEntries {
            let allowed = Set(mayReceive(entry, among: everyone).map(\.them))
            guard allowed.count < everyone.count else { continue }
            for peer in everyone where !allowed.contains(peer.them) {
                out[peer.them, default: []].insert(entry.feedKey, entry.seq)
            }
        }
        cachedWithheld = out
        return out
    }

    func addressed(_ sending: [Entry]) -> (rounds: [(peers: [Peer], entries: [Entry])], unaddressed: [Entry]) {
        let everyone = peers()
        var byAudience: [[ParticipantID]: [Entry]] = [:]
        var unaddressed: [Entry] = []
        for entry in sending {
            let who = mayReceive(entry, among: everyone).map(\.them)
                .sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
            if who.isEmpty {
                unaddressed.append(entry)
            } else {
                byAudience[who, default: []].append(entry)
            }
        }
        func naming(_ who: [ParticipantID]) -> Data {
            who.reduce(into: Data()) { $0.append($1.rawValue) }
        }
        let order = byAudience.keys.sorted {
            naming($0).lexicographicallyPrecedes(naming($1))
        }
        let addressable = Dictionary(uniqueKeysWithValues: everyone.map { ($0.them, $0) })
        var rounds = order.map { who in
            (peers: who.compactMap { addressable[$0] }, entries: byAudience[who] ?? [])
        }
        let covered = Set(rounds.flatMap { $0.peers.map(\.them) })
        for peer in everyone where !covered.contains(peer.them) {
            rounds.append((peers: [peer], entries: []))
        }
        return (rounds, unaddressed)
    }

    static func withholdsKeys(viewMayBeStale: Bool, roomHasAbsences: Bool) -> Bool {
        viewMayBeStale && roomHasAbsences
    }

    func grantsOwed() throws -> [(to: Peer, grant: EpochGrant, receipt: String)] {
        guard let enrolment else { return [] }
        var owed: [(to: Peer, grant: EpochGrant, receipt: String)] = []

        for room in persisted.knownRooms {
            guard let chain = chains[room], let epoch = chain.highestKnownEpoch
            else { continue }

            if Self.withholdsKeys(
                viewMayBeStale: viewMayBeStale, roomHasAbsences: !roster(of: room).absent.isEmpty)
            {
                Diagnostics.sync.notice(
                    "mailbox sync: holding this room's keys for a round — something did not verify and somebody here is out of the room")
                continue
            }
            let secret = try chain.secret(for: epoch)

            let isWall = room == outpostRoom(for: enrolment.identity.id)
            let roomRoster = roster(of: room)
            let floors: [ParticipantID: UInt64?] = isWall
                ? projection.outpostFloors(of: enrolment.identity.id, opening: payloadOpener())
                : roomRoster.everyHistoryFloor.mapValues { Optional($0.rawValue) }
            let owedAFloor = isWall
                ? []
                : Set(
                    roomRoster.members.filter {
                        roomRoster.invitation(of: $0).map { !$0.sharesHistory } ?? false
                            && roomRoster.historyFloor(of: $0) == nil
                    })
            let targets: [ParticipantID] =
                isWall
                ? outpostReaders().sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
                : Array(notShutOut(roster(of: room).rewrapTargets(of: enrolment.identity.id)))

            for target in targets {
                if owedAFloor.contains(target) {
                    Diagnostics.sync.notice(
                        "mailbox sync: holding this room's keys from a new member until their history is closed")
                    continue
                }
                let floor = (floors[target] ?? nil).map(EpochNumber.init(rawValue:))
                let link = floor.map { epoch > $0 ? chain.link(at: epoch) : nil } ?? chain.link(at: epoch)
                let links = floor.map { ceiling in chain.everyLink.filter { $0.epoch > ceiling } }
                    ?? chain.everyLink
                let receipt = Self.grantReceipt(
                    room: room, epoch: epoch, target: target, floor: floor)
                guard !issuedGrants.contains(receipt) else { continue }

                guard let keys = replica.registry(for: target)?.identity,
                    let pairwise = try? PairwiseSecret.derive(
                        mine: enrolment.identity, theirs: keys)
                else { continue }

                owed.append(
                    (
                        to: Peer(secret: pairwise, them: target, me: enrolment.identity.id),
                        grant: try EpochGrant.issue(
                            secret, at: epoch, in: room, link: link, links: links, to: pairwise),
                        receipt: receipt
                    ))
            }
        }
        return owed
    }

    private static func grantReceipt(
        room: ConversationID, epoch: EpochNumber, target: ParticipantID, floor: EpochNumber?
    ) -> String {
        let since = floor.map { String($0.rawValue) } ?? "all"
        return
            "\(room.stableName)|\(epoch.rawValue)|\(target.rawValue.base64EncodedString())|\(since)"
    }

    func adopt(_ grant: EpochGrant, from peer: Peer) async throws {
        guard !replica.closedRooms.contains(grant.room) else {
            Diagnostics.sync.notice("adopt: refused a key for a conversation this member deleted")
            return
        }
        let held = chains[grant.room]
        var chain = held ?? EpochChain(room: grant.room)
        do {
            try chain.adopt(grant, using: peer.secret)
        } catch {
            Diagnostics.sync.error(
                "adopt: could not open the epoch key for a room (epoch \(grant.epoch.rawValue, privacy: .public)) — \(String(describing: error), privacy: .public)")
            return
        }
        let taughtSomething =
            chain.knownEpochs.count != held?.knownEpochs.count
            || chain.everyLink.count != held?.everyLink.count
        chains[grant.room] = chain

        if !persisted.knownRooms.contains(grant.room) {
            persisted.knownRooms.append(grant.room)
        }
        if taughtSomething {
            try await persistEpoch(
                try chain.secret(for: grant.epoch), at: grant.epoch, for: grant.room)
            try await unwindEpochs(
                in: grant.room,
                bounded: (grant.link == nil && grant.links.isEmpty)
                    || walkStopsShort(in: grant.room))
        }

        if grant.room == outpostRoom(for: peer.them) {
            if persisted.outpostSeenThrough[peer.them] == nil {
                persisted.outpostSeenThrough[peer.them] = clock.now
                await saveSeenMarks()
            }
        }
        if grant.room == outpostRoom(for: peer.them), !hasAskedForWall.contains(peer.them) {
            hasAskedForWall.insert(peer.them)
            await askForWall(of: peer.them)
        }
        Diagnostics.sync.notice(
            """
            adopt: \(taughtSomething ? "installed" : "already held", privacy: .public) \
            epoch \(grant.epoch.rawValue, privacy: .public) for a room \
            (link \(grant.link == nil ? "absent" : "present", privacy: .public), \
            now holding \(self.chains[grant.room]?.knownEpochs.count ?? 0, privacy: .public) epoch(s))
            """)

        guard grant.room != outpostRoom(for: peer.them) else { return }
        await announceOrReport("your name into a room you were given a key for") {
            try await announceProfile(in: grant.room)
        }
    }
}
