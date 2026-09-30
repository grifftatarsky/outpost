import CarpenterKit
import CryptoKit
import Foundation

// MARK: Who can be reached, and the room keys they are owed

extension AppSession {
    func peers() -> [Peer] {
        let untold = waitingToBeTold
        return everyPeer().filter { !untold.contains($0.them) }
    }

    func everyPeer() -> [Peer] {
        guard let me = enrolment?.identity.id else { return [] }
        return reachableParticipants().compactMap { participant in
            pairwiseSecret(with: participant).map { Peer(secret: $0, them: participant, me: me) }
        }
    }

    var hasSomebodyToReach: Bool {
        reachableParticipants().contains { pairwiseSecret(with: $0) != nil }
    }

    private func reachableParticipants() -> Set<ParticipantID> {
        guard let me = enrolment?.identity.id else { return [] }
        let reachable = notShutOut(addressable())
        return replica.knownParticipants.filter { $0 != me && reachable.contains($0) }
    }

    private func addressable() -> Set<ParticipantID> {
        guard let me = enrolment?.identity.id else { return [] }
        let shared = sharedParticipants()
        var reachable = shared
        for room in projection.namedRoomIDs() { reachable.formUnion(roster(of: room).absent) }
        for repair in persisted.repairs { reachable.formUnion(repair.asked) }
        for duty in persisted.repairDuties { reachable.insert(duty.from) }
        reachable.remove(me)
        return reachable.subtracting(quiet(besides: shared))
    }

    func sharedParticipants() -> Set<ParticipantID> {
        guard let me = enrolment?.identity.id else { return [] }
        let projected = projection
        let rooms = projected.namedRoomIDs()
        var shared: Set<ParticipantID> = []
        for room in rooms {
            let roster = roster(of: room)
            shared.formUnion(roster.members)
            shared.formUnion(roster.requests.keys)
        }
        shared.formUnion(outpostAccess.audience(at: clock.now))
        shared.formUnion(projected.outpostAuthors().map(\.id))
        for invitation in invitationsOutsideTheirRoom() {
            shared.insert(invitation.attestation.inviter)
        }
        if rooms.isEmpty {
            shared.formUnion(persisted.pairBook.keys)
        }
        shared.remove(me)
        return shared
    }

    func outOfTouch() -> Set<ParticipantID> {
        quiet(besides: sharedParticipants())
    }

    private func quiet(besides shared: Set<ParticipantID>) -> Set<ParticipantID> {
        let longAgo = clock.now.addingTimeInterval(-SyncSession.packetWaitsFor)
        return Set(persisted.pairBook.compactMap { peer, entry in
            guard let stopped = entry.sharedNothingSince, stopped <= longAgo, !shared.contains(peer) else { return nil }
            return peer
        })
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
            guard let chain = chains[room] else { continue }

            if Self.withholdsKeys(
                viewMayBeStale: viewMayBeStale, roomHasAbsences: !roster(of: room).absent.isEmpty)
            {
                Diagnostics.sync.notice(
                    "mailbox sync: holding this room's keys for a round — something did not verify and somebody here is out of the room")
                continue
            }

            let isWall = room == outpostRoom(for: enrolment.identity.id)
            let floors = isWall
                ? projection.outpostFloors(of: enrolment.identity.id, opening: payloadOpener())
                : [:]
            let targets: [ParticipantID] =
                isWall
                ? outpostReaders().sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
                : Array(notShutOut(roster(of: room).rewrapTargets(of: enrolment.identity.id)))

            for passing in keysToPassOn(in: room) {
                let epoch = passing.epoch
                let secret = passing.secret
                var passesOn: Bool?
                for target in targets {
                    let floor = isWall ? (floors[target] ?? nil).map(EpochNumber.init(rawValue:)) : nil
                    let link = floor.map { epoch > $0 ? passing.link : nil } ?? passing.link
                    let links = floor.map { ceiling in chain.everyLink.filter { $0.epoch > ceiling } }
                        ?? chain.everyLink
                    let devices = deviceRecipients(of: target)
                    guard !devices.isEmpty else { continue }
                    let receipt = Self.grantReceipt(
                        room: room, epoch: epoch, key: secret, target: target, floor: floor, devices: devices)
                    guard !issuedGrants.contains(receipt) else { continue }

                    guard let pairwise = pairwiseSecret(with: target) else { continue }
                    if passesOn == nil { passesOn = holdsWhatItsMakerSaw(epoch, in: room, under: secret) }
                    guard passesOn == true else {
                        Diagnostics.sync.notice(
                            "mailbox sync: holding a room's newest key until everything its maker had seen has arrived")
                        break
                    }

                    owed.append(
                        (
                            to: Peer(secret: pairwise, them: target, me: enrolment.identity.id),
                            grant: try EpochGrant.issue(
                                secret, at: epoch, in: room, link: link, links: links, to: pairwise,
                                devices: devices
                            ).signed(by: enrolment.device, from: enrolment.identity.id, to: target),
                            receipt: receipt
                        ))
                }
            }
        }
        return owed
    }

    private func holdsWhatItsMakerSaw(_ epoch: EpochNumber, in room: RoomID, under secret: EpochSecret) -> Bool {
        guard epoch != .initial else { return true }
        let held = entriesByHash
        return projection.keyChanges(in: room, opening: payloadOpener()).contains { made in
            made.change.link.epoch == epoch && made.change.isAuthentic(under: secret)
                && made.change.heads.allSatisfy { held[$0] != nil }
        }
    }

    func writingKey(of room: RoomID) -> TrustedKey? {
        trustedKeys(of: room).first
    }

    func keysToPassOn(in room: RoomID) -> [TrustedKey] {
        cached(\.cachedKeysToPassOn, room) {
            guard let me = enrolment?.identity.id else { return [] }
            let newest = trustedKeys(of: room)
            let heads = newest.filter { $0.maker == me } + newest.filter { $0.maker != me }
            return heads + straysBelow(heads, in: room)
        }
    }

    private func straysBelow(_ heads: [TrustedKey], in room: RoomID) -> [TrustedKey] {
        guard var epoch = heads.first?.epoch, let chain = chains[room],
            chain.heldKeyCount > chain.knownEpochs.count
        else { return [] }
        let makers = outpostOwner(of: room).map { Set([$0]) } ?? roster(of: room).members
        let changes = projection.keyChanges(in: room, opening: payloadOpener())
        var reachable = Set(heads.map(\.secret))
        var strays: [TrustedKey] = []
        while let below = epoch.previous {
            reachable = Set(reachable.compactMap { chain.unwrapping(epoch, under: $0) })
            epoch = below
            for secret in chain.heldSecrets(at: epoch) where !reachable.contains(secret) {
                guard let stray = trustedKey(secret, at: epoch, in: chain, makers: makers, changes: changes)
                else { continue }
                strays.append(stray)
                reachable.insert(secret)
            }
        }
        return strays
    }

    private func trustedKeys(of room: RoomID) -> [TrustedKey] {
        cached(\.cachedTrustedKeys, room) {
            guard let chain = chains[room] else { return [] }
            let makers = outpostOwner(of: room).map { Set([$0]) } ?? roster(of: room).members
            let changes = projection.keyChanges(in: room, opening: payloadOpener())
            for epoch in chain.knownEpochs.sorted(by: >) {
                let trusted = chain.heldSecrets(at: epoch).compactMap { secret in
                    trustedKey(secret, at: epoch, in: chain, makers: makers, changes: changes)
                }
                if !trusted.isEmpty {
                    return trusted.sorted { $0.secret.fingerprint.lexicographicallyPrecedes($1.secret.fingerprint) }
                }
            }
            return []
        }
    }

    private func trustedKey(
        _ secret: EpochSecret, at epoch: EpochNumber, in chain: EpochChain, makers: Set<ParticipantID>,
        changes: [(author: ParticipantID, change: EpochChangeBody)]
    ) -> TrustedKey? {
        guard epoch != .initial else { return TrustedKey(epoch: epoch, secret: secret, link: nil, maker: nil) }
        let records = changes.filter { $0.change.link.epoch == epoch && $0.change.isAuthentic(under: secret) }
        guard !records.isEmpty else {
            guard (try? chain.secret(for: epoch)) == secret, let giver = chain.giver(of: secret, at: epoch),
                makers.contains(giver)
            else { return nil }
            return TrustedKey(epoch: epoch, secret: secret, link: chain.link(at: epoch), maker: nil)
        }
        return records.first { makers.contains($0.author) }.map {
            TrustedKey(epoch: epoch, secret: secret, link: $0.change.link, maker: $0.author)
        }
    }

    func deviceRecipients(of participant: ParticipantID) -> [DeviceRecipient] {
        guard let registry = replica.registry(for: participant) else { return [] }
        let devices = registry.activeDevices.sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
        return devices.compactMap { device in
            registry.agreementKey(for: device).map { DeviceRecipient(device: device, agreementKey: $0) }
        }
    }

    private static func grantReceipt(
        room: RoomID, epoch: EpochNumber, key: EpochSecret, target: ParticipantID, floor: EpochNumber?,
        devices: [DeviceRecipient]
    ) -> String {
        let since = floor.map { String($0.rawValue) } ?? "all"
        let to = devices.map { $0.device.rawValue.base64EncodedString() }.joined(separator: ",")
        let which = key.fingerprint.base64EncodedString()
        return
            "\(room.rawValue.uuidString)|\(epoch.rawValue)|\(which)|\(target.rawValue.base64EncodedString())|\(since)|\(to)"
    }

    private func invitersInto(_ room: RoomID) -> Set<ParticipantID> {
        Set(persisted.acceptedInvitations.filter { $0.attestation.room == room }.map(\.attestation.inviter))
    }

    private func mayGiveTheFirstKey(_ giver: ParticipantID, to room: RoomID, opening chain: EpochChain) -> Bool {
        let inviters = invitersInto(room)
        guard inviters.isEmpty else { return inviters.contains(giver) }
        return replica.allEntries.contains { $0.room == room && $0.author != giver && $0.opened(using: chain) != nil }
    }

    private func mayGiveAKeyBeforeTheHistory(_ giver: ParticipantID, to room: RoomID) -> Bool {
        let roster = roster(of: room)
        return roster.members.isEmpty && !roster.absent.contains(giver) && invitersInto(room).contains(giver)
    }

    private func keepUntilShownIn(_ grant: EpochGrant, from giver: ParticipantID, storedAt: Date) -> Bool {
        guard persisted.acceptedInvitations.contains(where: { $0.attestation.room == grant.room }),
            !roster(of: grant.room).absent.contains(giver)
        else { return false }
        persisted.grantsWaiting.removeAll { $0.grant.room == grant.room && $0.from == giver }
        persisted.grantsWaiting.append(ForwardedGrant(from: giver, grant: grant, storedAt: storedAt))
        Diagnostics.sync.notice("adopt: keeping a room key until this phone shows whoever gave it as in the room")
        return true
    }

    func adoptGrantsThatWaited() async throws {
        guard let me = enrolment?.identity.id else { return }
        for waiting in persisted.grantsWaiting where chains[waiting.grant.room] != nil {
            let roster = roster(of: waiting.grant.room)
            let isIn = roster.members.contains(waiting.from)
            guard isIn || roster.absent.contains(waiting.from) else { continue }
            persisted.grantsWaiting.removeAll { $0 == waiting }
            guard isIn, let secret = pairwiseSecret(with: waiting.from), let storedAt = waiting.storedAt else { continue }
            try await adopt(waiting.grant, from: Peer(secret: secret, them: waiting.from, me: me), storedAt: storedAt)
        }
    }

    private func outpostOwner(of room: RoomID) -> ParticipantID? {
        guard let me = enrolment?.identity.id else { return nil }
        if room == outpostRoom(for: me) { return me }
        return replica.knownParticipants.first { outpostRoom(for: $0) == room }
    }

    func adopt(_ grant: EpochGrant, from peer: Peer, storedAt: Date) async throws {
        guard let registry = replica.registry(for: peer.them),
            grant.isSigned(from: peer.them, to: peer.me, by: registry, storedAt: storedAt)
        else {
            Diagnostics.sync.error(
                "adopt: refused a room key that no device of its sender signed while that device counted")
            return
        }
        guard !replica.closedRooms.contains(grant.room) else {
            Diagnostics.sync.notice("adopt: refused a key for a conversation this member deleted")
            return
        }
        let owner = outpostOwner(of: grant.room)
        let held = chains[grant.room]
        if let owner {
            guard owner == peer.them else {
                Diagnostics.sync.notice("adopt: refused a key to an Outpost from somebody who does not own it")
                return
            }
        } else if held != nil, !roster(of: grant.room).members.contains(peer.them),
            !mayGiveAKeyBeforeTheHistory(peer.them, to: grant.room)
        {
            if !keepUntilShownIn(grant, from: peer.them, storedAt: storedAt) {
                Diagnostics.sync.notice("adopt: refused a key from somebody the room does not show as in it")
            }
            return
        }
        var chain = held ?? EpochChain(room: grant.room)
        do {
            var opened = false
            var lastError: any Error = CryptoError.openFailed
            for secret in [peer.secret] + alternateSecrets(with: peer.them).filter({ $0 != peer.secret }) {
                do {
                    try chain.adopt(grant, using: secret, as: enrolment?.device, from: peer.them)
                    opened = true
                    break
                } catch CryptoError.notSealedForThisDevice {
                    throw CryptoError.notSealedForThisDevice
                } catch {
                    lastError = error
                }
            }
            if !opened { throw lastError }
        } catch CryptoError.notSealedForThisDevice {
            persisted.siblingMail.forward(ForwardedGrant(from: peer.them, grant: grant, storedAt: storedAt))
            Diagnostics.sync.notice(
                "adopt: a room key was sealed for this member's other devices, not this one; passing it on")
            sendOwnEntries()
            return
        } catch {
            Diagnostics.sync.error(
                "adopt: could not open the epoch key for a room (epoch \(grant.epoch.rawValue, privacy: .public)) — \(String(describing: error), privacy: .public)")
            return
        }
        guard held != nil || owner != nil || mayGiveTheFirstKey(peer.them, to: grant.room, opening: chain) else {
            if !keepUntilShownIn(grant, from: peer.them, storedAt: storedAt) {
                Diagnostics.sync.notice("adopt: refused a first key for a room from somebody who did not invite this member to it")
            }
            return
        }
        let taughtSomething =
            chain.heldKeyCount != held?.heldKeyCount
            || chain.everyLink.count != held?.everyLink.count
        chains[grant.room] = chain
        if held == nil, persisted.restoredWithTheRecoveryKey,
            outpostOwner(of: grant.room).map({ $0 == enrolment?.identity.id }) ?? true
        {
            persisted.rekeyBeforeWriting.insert(grant.room)
        }

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

struct TrustedKey {
    let epoch: EpochNumber
    let secret: EpochSecret
    let link: EpochLink?
    let maker: ParticipantID?
}
