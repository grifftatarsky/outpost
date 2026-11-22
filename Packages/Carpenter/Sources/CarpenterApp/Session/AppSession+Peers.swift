import CarpenterKit
import CryptoKit
import Foundation
import os

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
        let shared = sharedParticipants()
        return peopleSomethingIsOwedTo(besides: shared).subtracting(quiet(besides: shared))
    }

    private func peopleSomethingIsOwedTo(besides shared: Set<ParticipantID>) -> Set<ParticipantID> {
        guard let me = enrolment?.identity.id else { return [] }
        var people = shared
        for room in projection.namedRoomIDs() { people.formUnion(roster(of: room).absent) }
        for repair in persisted.repairs { people.formUnion(repair.asked) }
        for duty in persisted.repairDuties { people.insert(duty.from) }
        people.remove(me)
        return people
    }

    func peopleInTouch() -> Set<ParticipantID> {
        guard let me = enrolment?.identity.id else { return [] }
        var people = peopleSomethingIsOwedTo(besides: sharedParticipants())
        people.formUnion(persisted.pairBook.keys)
        people.formUnion(persisted.preferences.blockedPeople)
        people.formUnion(persisted.codeClaims.map(\.peer))
        people.remove(me)
        return people
    }

    public static let mostNewcomersFromOnePersonADay = 32

    func whoToMeet(through person: ParticipantID) -> WhoToMeet {
        var known = sharedParticipants().union(peopleInTouch())
        let named = projection.namedRoomIDs()
        for room in named { known.formUnion(roster(of: room).absent) }
        let ours = Set(rooms.map(\.id)).union(named).union(persisted.knownRooms)
            .union(persisted.acceptedInvitations.map(\.attestation.room)).union(known.map(RoomID.outpost(of:)))
        let day = SyncSession.window(at: clock.now)
        let spent = persisted.newcomersFrom[person].flatMap { $0.day == day ? $0.count : nil } ?? 0
        return WhoToMeet(known: known, rooms: ours, newcomers: Self.mostNewcomersFromOnePersonADay - spent)
    }

    func noteNewcomers(_ count: Int, from person: ParticipantID) {
        guard count > 0 else { return }
        let day = SyncSession.window(at: clock.now)
        let before = persisted.newcomersFrom[person].flatMap { $0.day == day ? $0.count : nil } ?? 0
        persisted.newcomersFrom[person] = DailyCount(day: day, count: before + count)
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

    func grantsOwed() throws -> [(to: Peer, grant: EpochGrant, receipt: String, key: Data)] {
        guard let enrolment else { return [] }
        var owed: [(to: Peer, grant: EpochGrant, receipt: String, key: Data)] = []

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
                    if let floor, epoch < floor { continue }
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
                            receipt: receipt, key: secret.fingerprint
                        ))
                }
            }
        }
        return owed
    }

    func noteDevicesKeysAreSealedTo(by owed: [(to: Peer, grant: EpochGrant, receipt: String, key: Data)]) -> Bool {
        var sealed = persisted.keysSealed.filter { chains[$0.room] != nil }
        for grant in owed where outpostOwner(of: grant.grant.room) == nil {
            for seal in grant.grant.sealedFor {
                sealed.insert(KeySealed(room: grant.grant.room, key: grant.key, person: grant.to.them, device: seal.device))
            }
        }
        for room in Set(owed.map(\.grant.room)) {
            let passedOn = Set(keysToPassOn(in: room).map(\.secret.fingerprint))
            sealed = sealed.filter { $0.room != room || passedOn.contains($0.key) }
        }
        guard sealed != persisted.keysSealed else { return false }
        persisted.keysSealed = sealed
        return true
    }

    func oweNewKeysWhereARemovedDeviceHoldsOne() async {
        let gone = persisted.keysSealed.filter { sealed in
            replica.registry(for: sealed.person).map { !$0.activeDevices.contains(sealed.device) } ?? false
        }
        guard !gone.isEmpty else { return }
        for room in Set(gone.map(\.room)) where chains[room] != nil {
            guard let writing = writingKey(of: room)?.secret.fingerprint,
                gone.contains(where: { $0.room == room && $0.key == writing })
            else { continue }
            persisted.rekeyBeforeWriting.insert(room)
            Diagnostics.sync.notice(
                "mailbox sync: this room's key was sealed to a device its member has since removed; it gets a new one")
        }
        persisted.keysSealed.subtract(gone)
        await persistOrReport("that a room needs a key a removed device was never sent") { try await saveState() }
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

    private func keyMakers(of room: RoomID) -> Set<ParticipantID> {
        if let owner = outpostOwner(of: room) { return [owner] }
        let roster = roster(of: room)
        return roster.members.union(roster.departures.keys).subtracting(roster.removals.keys)
    }

    func keyRecords(in room: RoomID) -> (EpochNumber, EpochSecret) -> Set<ParticipantID> {
        var changes: [(author: ParticipantID, change: EpochChangeBody)]?
        return { [self] epoch, secret in
            let made = changes ?? projection.keyChanges(in: room, opening: payloadOpener())
            changes = made
            let records = made.filter { $0.change.link.epoch == epoch && $0.change.isAuthentic(under: secret) }
            return Set(records.map(\.author))
        }
    }

    func writesBelowAKeyARemovedMemberMade(in room: RoomID) -> Bool {
        guard outpostOwner(of: room) == nil, let chain = chains[room], let top = chain.highestKnownEpoch else {
            return false
        }
        let writing = writingKey(of: room)?.epoch ?? .initial
        let removed = Set(roster(of: room).removals.keys)
        guard writing < top, !removed.isEmpty else { return false }
        let changes = projection.keyChanges(in: room, opening: payloadOpener())
        return chain.heldNumbers.contains { epoch in
            epoch > writing
                && chain.heldSecrets(at: epoch).contains { secret in
                    chain.giver(of: secret, at: epoch).map { removed.contains($0.person) } == true
                        || changes.contains {
                            $0.change.link.epoch == epoch && removed.contains($0.author)
                                && $0.change.isAuthentic(under: secret)
                        }
                }
        }
    }

    private func straysBelow(_ heads: [TrustedKey], in room: RoomID) -> [TrustedKey] {
        guard var above = heads.first?.epoch, let chain = chains[room],
            chain.heldKeyCount > chain.knownEpochs.count
        else { return [] }
        let makers = keyMakers(of: room)
        let changes = projection.keyChanges(in: room, opening: payloadOpener())
        var reachable = Set(heads.map(\.secret))
        var strays: [TrustedKey] = []
        for epoch in chain.heldNumbers where epoch < above {
            reachable = above.previous == epoch ? Set(reachable.compactMap { chain.unwrapping(above, under: $0) }) : []
            above = epoch
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
            let makers = keyMakers(of: room)
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
                makers.contains(giver.person), let device = giver.device,
                replica.registry(for: giver.person)?.activeDevices.contains(device) == true,
                keyChangesRefused[chain.room]?.contains(where: {
                    $0.link.epoch == epoch && $0.isAuthentic(under: secret)
                }) != true
            else { return nil }
            return TrustedKey(epoch: epoch, secret: secret, link: chain.link(at: epoch), maker: nil)
        }
        return records.first { makers.contains($0.author) }.map {
            TrustedKey(epoch: epoch, secret: secret, link: $0.change.link, maker: $0.author)
        }
    }

    static let mostKeyChangesRefusedKept = 64

    func noteKeyChangesRefused(among entries: [Entry]) {
        var noted = false
        for entry in entries {
            let room = entry.sealingRoom
            guard let chain = chains[room], let payload = entry.opened(using: chain), payload.type == .epochChange,
                let change = try? payload.decode(EpochChangeBody.self),
                keyChangesRefused[room]?.contains(change) != true
            else { continue }
            let kept = (keyChangesRefused[room] ?? []) + [change]
            keyChangesRefused[room] = Array(kept.suffix(Self.mostKeyChangesRefusedKept))
            noted = true
        }
        guard noted else { return }
        cachedTrustedKeys = [:]
        cachedKeysToPassOn = [:]
    }

    static func entriesTurnedAway(_ arriving: [Entry], from before: Replica, to after: Replica) -> [Entry] {
        let refused = arriving.filter { entry in
            !after.entries(in: entry.feedKey, at: entry.seq).contains { $0.hash == entry.hash }
        }
        guard before.knownRevocations.count != after.knownRevocations.count else { return refused }
        let kept = Set(after.allEntries.map(\.hash))
        return refused + before.allEntries.filter { !kept.contains($0.hash) }
    }

    func deviceRecipients(of participant: ParticipantID) -> [DeviceRecipient] {
        guard let registry = replica.registry(for: participant) else { return [] }
        let devices = registry.activeDevices.sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
        return devices.compactMap { device in
            registry.sealingKey(for: device).map { DeviceRecipient(device: device, sealingKey: $0) }
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

    private func outgrowsTheLog(_ chain: EpochChain) -> Bool {
        let held = chain.heldNumbers.count
        guard held > EpochChain.mostNumbersTheLogHasNotShown else { return false }
        let shown = Set(projection.keyChanges(in: chain.room, opening: payloadOpener()).map(\.change.link.epoch))
        return held > shown.count + EpochChain.mostNumbersTheLogHasNotShown
    }

    func readerLostADevice(from before: Replica, to after: Replica) -> Bool {
        guard let me = enrolment?.identity.id, chains[outpostRoom(for: me)] != nil else { return false }
        return outpostReaders().contains { reader in
            let was = before.registry(for: reader)?.activeDevices ?? []
            let now = after.registry(for: reader)?.activeDevices ?? []
            return !was.isSubset(of: now)
        }
    }

    func outpostOwner(of room: RoomID) -> ParticipantID? {
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
        let records = keyRecords(in: grant.room)
        do {
            var opened = false
            var lastError: any Error = CryptoError.openFailed
            for secret in [peer.secret] + alternateSecrets(with: peer.them).filter({ $0 != peer.secret }) {
                do {
                    try chain.adopt(
                        grant, using: secret, as: enrolment?.device, from: peer.them,
                        recordedBy: { records(grant.epoch, $0) })
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
        guard !outgrowsTheLog(chain) else {
            Diagnostics.sync.error("adopt: refused a key that would put this room's chain too far beyond what its log shows")
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
