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
                guard let keys = replica.registry(for: participant)?.identity,
                    let secret = try? PairwiseSecret.derive(mine: enrolment.identity, theirs: keys)
                else { return nil }
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
        let posts = Set(sending.filter { $0.room == nil }.map(\.hash))
        let carryingOwnPost = !posts.isDisjoint(with: unsentWallPosts)
        guard carryingOwnPost || !wallsWrittenOn.isEmpty else { return [] }

        let readers = outpostReaders()
        return peers().filter {
            if wallsWrittenOn.contains($0.them) { return true }
            return carryingOwnPost && readers.contains($0.them)
                && persisted.wantsOutpostBell.contains($0.them)
        }
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
            let floors = isWall
                ? projection.outpostFloors(of: enrolment.identity.id, opening: payloadOpener())
                : [:]
            let targets: [ParticipantID] =
                isWall
                ? outpostReaders().sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
                : Array(notShutOut(roster(of: room).rewrapTargets(of: enrolment.identity.id)))

            for target in targets {
                let floor = isWall ? (floors[target] ?? nil).map(EpochNumber.init(rawValue:)) : nil
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
        room: RoomID, epoch: EpochNumber, target: ParticipantID, floor: EpochNumber?
    ) -> String {
        let since = floor.map { String($0.rawValue) } ?? "all"
        return
            "\(room.rawValue.uuidString)|\(epoch.rawValue)|\(target.rawValue.base64EncodedString())|\(since)"
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
