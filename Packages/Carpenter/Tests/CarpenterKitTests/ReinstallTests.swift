import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@MainActor
@Suite("A reinstall is the same device, once it has read back where it had got to", .serialized)
struct ReinstallTests {
    private struct Rig {
        let relay: InMemoryEntrySync.Relay
        let mailbox: InMemoryMailbox
        let keychain: InMemoryKeychainStore
        let clock: TestClock
        let alice: AppSession
        let bob: AppSession
        let room: ConversationID
    }

    private func settle(_ sessions: [AppSession], _ mailbox: InMemoryMailbox, rounds: Int = 4) async throws {
        for _ in 0..<rounds {
            for session in sessions { _ = try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func caughtUp(_ session: AppSession) async {
        let deadline = Date().addingTimeInterval(5)
        while session.isCatchingUp, Date() < deadline {
            await session.learnWhereThisDeviceHadGotTo()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func rig() async throws -> Rig {
        let relay = InMemoryEntrySync.Relay()
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let keychain = InMemoryKeychainStore()
        let alice = TestSession.make(keychain: keychain, clock: clock)
        await alice.load()
        alice.syncDevices(through: InMemoryEntrySync(relay: relay))
        try await alice.createIdentity(displayName: "Alice")
        let bob = TestSession.make(clock: clock)
        await bob.load()
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await settle([alice, bob], mailbox, rounds: 6)
        return Rig(
            relay: relay, mailbox: mailbox, keychain: keychain, clock: clock, alice: alice, bob: bob,
            room: room)
    }

    private func reinstall(_ rig: Rig, at directory: URL? = nil) async -> AppSession {
        let session = TestSession.make(keychain: rig.keychain, at: directory, clock: rig.clock)
        await session.load()
        return session
    }

    private func feed(of session: AppSession, in room: ConversationID) throws -> FeedKey {
        let enrolment = try #require(session.enrolment)
        return FeedKey(author: enrolment.identity.id, device: enrolment.device.id, conversation: room)
    }

    private func top(of feed: FeedKey, in session: AppSession) -> UInt64 {
        session.replica.allEntries.filter { $0.feedKey == feed }.map(\.seq).max() ?? 0
    }

    private func ownRecord(_ rig: Rig, of device: DeviceID, identity: Identity) async throws -> [SiblingFeed] {
        let reader = InMemoryEntrySync(relay: rig.relay)
        return try await reader.ownRecords(of: device).map { try $0.open(with: identity, from: device) }
    }

    // MARK: Carrying on

    @Test("A reinstalled device carries on from the next position, and nobody sees a fork")
    func aReinstallCarriesOn() async throws {
        let rig = try await rig()
        for index in 1...3 { try await rig.alice.send("before \(index)", to: rig.room) }
        try await settle([rig.alice, rig.bob], rig.mailbox)
        let feed = try feed(of: rig.alice, in: rig.room)
        let before = top(of: feed, in: rig.alice)
        #expect(
            !rig.bob.replica.entries(in: feed, at: before).isEmpty,
            "precondition: Bob never received Alice's last message")

        let again = await reinstall(rig)
        #expect(again.enrolment?.device.id == feed.device, "the same device came back as a different one")
        #expect(again.isCatchingUp, "a device with its keys and nothing else thought it knew its place")
        #expect(
            again.state == .ready,
            "a member whose name is on its way back was asked for it, and the answer could not be saved")
        await #expect(throws: AppSessionError.catchingUp) {
            try await again.send("too soon", to: rig.room)
        }

        again.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await caughtUp(again)
        #expect(!again.isCatchingUp, "it never finished reading its own records")

        try await again.send("after the reinstall", to: rig.room)
        #expect(top(of: feed, in: again) == before + 1, "the reinstall reused or skipped a position")

        try await settle([again, rig.bob], rig.mailbox)
        #expect(rig.bob.replica.forks.isEmpty, "Bob holds two entries at one of Alice's positions")
        #expect(
            rig.bob.messages(in: rig.room).map(\.body).contains("after the reinstall"),
            "Bob never received what the reinstalled device wrote")
    }

    @Test("Nothing is written or published before the device has read its own records")
    func nothingBeforeTheRecords() async throws {
        let rig = try await rig()
        for index in 1...3 { try await rig.alice.send("before \(index)", to: rig.room) }
        try await settle([rig.alice, rig.bob], rig.mailbox)
        let identity = try #require(rig.alice.enrolment?.identity)
        let device = try #require(rig.alice.enrolment?.device.id)
        let recorded = try await ownRecord(rig, of: device, identity: identity)
        let positions = try #require(recorded.first { $0.entries.isEmpty }?.positions)
        #expect(!positions.isEmpty, "precondition: the summary record held no positions")

        let again = await reinstall(rig)
        await rig.relay.failReads(true)
        again.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await again.learnWhereThisDeviceHadGotTo()
        #expect(again.isCatchingUp, "precondition: the device read its records although reads fail")
        _ = try await again.sync(through: rig.mailbox, media: rig.mailbox)
        again.sendOwnEntries()
        _ = await again.publishOwnRecordsNow()
        try? await Task.sleep(for: .milliseconds(50))
        await rig.relay.failReads(false)

        let still = try await ownRecord(rig, of: device, identity: identity)
        #expect(
            still.first { $0.entries.isEmpty }?.positions == positions,
            "the device wrote over its own record before reading it")
        #expect(
            still.first { !$0.entries.isEmpty }?.entries.count
                == recorded.first { !$0.entries.isEmpty }?.entries.count,
            "the entries record changed before it was read")
    }

    @Test("A first read that fails is tried again by the next round")
    func aFailedReadIsRetried() async throws {
        let rig = try await rig()
        await rig.relay.goOffline(true)
        let again = await reinstall(rig)
        again.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await again.learnWhereThisDeviceHadGotTo()
        #expect(again.isCatchingUp, "a device that could not read its records stopped waiting")

        await rig.relay.goOffline(false)
        _ = try await again.sync(through: rig.mailbox, media: rig.mailbox)
        #expect(!again.isCatchingUp, "the next round did not try to read the records again")
    }

    @Test("A device still catching up is still catching up after a relaunch")
    func itWaitsAcrossARelaunch() async throws {
        let rig = try await rig()
        let directory = URL.temporaryDirectory.appending(path: "reinstall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let again = await reinstall(rig, at: directory)
        #expect(again.isCatchingUp)
        let relaunched = await reinstall(rig, at: directory)
        #expect(
            relaunched.isCatchingUp,
            "a relaunch found a state file and forgot that the device had not read its records yet")
    }

    @Test("Room keys, contacts and its own history come back with the records")
    func keysAndHistoryComeBack() async throws {
        let rig = try await rig()
        try await rig.alice.send("what Alice said before", to: rig.room)
        try await settle([rig.alice, rig.bob], rig.mailbox)
        let bobID = try #require(rig.bob.enrolment?.identity.id)

        let again = await reinstall(rig)
        #expect(again.chains[rig.room] == nil, "precondition: the keys index survived the reinstall")
        again.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await caughtUp(again)

        #expect(again.chains[rig.room] != nil, "the room's key did not come back")
        #expect(
            again.messages(in: rig.room).map(\.body).contains("what Alice said before"),
            "the device's own history did not come back")
        #expect(
            again.replica.knownParticipants.contains(bobID),
            "the device no longer knows Bob, so it cannot reach him until he writes first")
    }

    @Test("Somebody known only from what others sent is still known after a reinstall")
    func aContactLearnedFromOthersIsKept() async throws {
        let rig = try await rig()
        let dave = Identity.generate()
        rig.alice.replica.introduce(dave.publicKeys)
        rig.alice.persisted.knownKeys.append(dave.publicKeys)
        _ = await rig.alice.publishOwnRecordsNow()

        let again = await reinstall(rig)
        again.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await caughtUp(again)
        #expect(
            again.replica.knownParticipants.contains(dave.id),
            "a contact the log does not name was forgotten, so nothing can reach them")
    }

    @Test("A deleted conversation's position survives, so rejoining never reuses a number")
    func aDeletedConversationKeepsItsPosition() async throws {
        let rig = try await rig()
        let elsewhere = try await rig.bob.createRoom(named: "Elsewhere")
        let invite = try await rig.bob.invite(
            joinerCode: rig.alice.identityCode(), joining: elsewhere, mailbox: nil)
        try await rig.alice.redeem(inviteCode: try invite.encoded())
        try await settle([rig.alice, rig.bob], rig.mailbox, rounds: 6)
        try await rig.alice.send("in the other room", to: elsewhere)
        try await rig.alice.leave(elsewhere)
        try await settle([rig.alice, rig.bob], rig.mailbox)
        try await rig.alice.deleteRoom(elsewhere)
        try await settle([rig.alice, rig.bob], rig.mailbox)
        let kept = try #require(rig.alice.persisted.ownHeads[elsewhere], "precondition: no position was kept")

        let again = await reinstall(rig)
        again.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await caughtUp(again)
        #expect(
            again.persisted.ownHeads[elsewhere] == kept,
            "the position in a deleted conversation did not come back")
    }

    @Test("A device that never published anything is not left waiting forever")
    func aDeviceThatNeverPublishedStarts() async throws {
        let keychain = InMemoryKeychainStore()
        let first = TestSession.make(keychain: keychain)
        await first.load()
        try await first.createIdentity(displayName: "Alice")

        let again = TestSession.make(keychain: keychain)
        await again.load()
        #expect(again.isCatchingUp)
        again.syncDevices(through: InMemoryEntrySync(relay: InMemoryEntrySync.Relay()))
        await caughtUp(again)
        #expect(!again.isCatchingUp, "a device with no record to read waited forever")
    }

    @Test("A device the member removed comes back as a new device, not as the one removed")
    func aRemovedDeviceComesBackNew() async throws {
        let relay = InMemoryEntrySync.Relay()
        let keychain = InMemoryKeychainStore()
        let phone = TestSession.make(keychain: keychain)
        await phone.load()
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        try await phone.createIdentity(displayName: "Alice")
        _ = try await phone.createRoom(named: "Lanterns")

        try await keychain.remove(IdentityStore.deviceKey)
        let pad = TestSession.make(keychain: keychain)
        await pad.load()
        pad.syncDevices(through: InMemoryEntrySync(relay: relay))
        let padDevice = try #require(pad.enrolment?.device.id)
        let deadline = Date().addingTimeInterval(5)
        while phone.replica.registry(for: try #require(phone.enrolment?.identity.id))?
            .standing(of: padDevice) == nil, Date() < deadline
        {
            await phone.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(10))
        }
        try await phone.revoke(padDevice)
        _ = await phone.publishOwnRecordsNow()

        let again = TestSession.make(keychain: keychain)
        await again.load()
        #expect(again.enrolment?.device.id == padDevice, "precondition: the pad's key did not survive")
        again.syncDevices(through: InMemoryEntrySync(relay: relay))
        await caughtUp(again)

        #expect(!again.isCatchingUp)
        let fresh = try #require(again.enrolment?.device.id)
        #expect(fresh != padDevice, "a removed device came back as itself")
        #expect(
            try await IdentityStore(keychain: keychain).loadDeviceKeys(
                for: try #require(again.enrolment?.identity.id))?.id == fresh,
            "the new device's key was not kept")
    }

    @Test("A device whose own record is ahead of it moves forward before it writes, and says so")
    func aDeviceBehindItsRecordMovesForward() async throws {
        let relay = InMemoryEntrySync.Relay()
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "ahead-\(UUID().uuidString)")
        let copy = URL.temporaryDirectory.appending(path: "ahead-copy-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: copy)
        }

        let alice = TestSession.make(keychain: keychain, at: directory, clock: clock)
        await alice.load()
        alice.syncDevices(through: InMemoryEntrySync(relay: relay))
        try await alice.createIdentity(displayName: "Alice")
        let bob = TestSession.make(clock: clock)
        await bob.load()
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await settle([alice, bob], mailbox, rounds: 6)
        try await alice.send("the copy has this", to: room)
        try await settle([alice, bob], mailbox)
        try FileManager.default.copyItem(at: directory, to: copy)

        for index in 1...2 { try await alice.send("the copy never saw \(index)", to: room) }
        try await settle([alice, bob], mailbox)
        let feed = try feed(of: alice, in: room)
        let before = top(of: feed, in: alice)

        let behind = TestSession.make(keychain: keychain, at: copy, clock: clock)
        await behind.load()
        #expect(!behind.isCatchingUp, "precondition: the copy had its state, so it was not catching up")
        #expect(top(of: feed, in: behind) < before, "precondition: the copy was not behind")
        behind.syncDevices(through: InMemoryEntrySync(relay: relay))
        let deadline = Date().addingTimeInterval(5)
        while behind.integrity.ownRecordAhead == 0, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        try await behind.send("from the copy, after catching up", to: room)
        #expect(top(of: feed, in: behind) == before + 1, "the copy wrote over its own later writing")
        #expect(behind.integrity.ownRecordAhead > 0, "the copy moved forward without saying so")
        try await settle([behind, bob], mailbox)
        #expect(bob.replica.forks.isEmpty, "Bob holds two entries at one of Alice's positions")

        let relaunched = TestSession.make(keychain: keychain, at: copy, clock: clock)
        await relaunched.load()
        #expect(
            relaunched.integrity.ownRecordAhead > 0,
            "a relaunch forgot that another copy of this device had been writing")
    }

    // MARK: The record goes first

    @Test("A message does not leave until the record that says it was written is saved")
    func aMessageWaitsForItsRecord() async throws {
        let rig = try await rig()
        await rig.relay.refuse([.summary])
        try await rig.alice.send("held until the record is saved", to: rig.room)
        try await settle([rig.alice, rig.bob], rig.mailbox)
        #expect(
            !rig.bob.messages(in: rig.room).map(\.body).contains("held until the record is saved"),
            "a message reached Bob before the record of it was saved")
        #expect(
            rig.alice.unsentEntries().contains { $0.conversation == rig.room && $0.author == rig.alice.enrolment?.identity.id },
            "a held message was drawn as though it had gone")

        await rig.relay.refuse([])
        try await settle([rig.alice, rig.bob], rig.mailbox)
        #expect(
            rig.bob.messages(in: rig.room).map(\.body).contains("held until the record is saved"),
            "once the record was saved the message still did not go")
    }

    @Test("Before device sync is attached, a round still holds back what its record does not count")
    func aRoundBeforeTheEngineHoldsBack() async throws {
        let rig = try await rig()
        let directory = URL.temporaryDirectory.appending(path: "early-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let alice = TestSession.make(keychain: rig.keychain, at: directory, clock: rig.clock)
        await alice.load()
        alice.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await caughtUp(alice)
        try await settle([alice, rig.bob], rig.mailbox)

        let relaunched = TestSession.make(keychain: rig.keychain, at: directory, clock: rig.clock)
        relaunched.recordsAreExpected = true
        await relaunched.load()
        try await relaunched.send("written before the engine was attached", to: rig.room)
        try await settle([relaunched, rig.bob], rig.mailbox)
        #expect(
            !rig.bob.messages(in: rig.room).map(\.body).contains("written before the engine was attached"),
            "a round that ran before device sync was attached sent writing no saved record counted")

        relaunched.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        let deadline = Date().addingTimeInterval(5)
        while relaunched.ownRecordIsBehind || relaunched.deviceSync == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        try await settle([relaunched, rig.bob], rig.mailbox)
        #expect(
            rig.bob.messages(in: rig.room).map(\.body).contains("written before the engine was attached"),
            "once the record was saved the writing still did not go")
    }

    @Test("An entries record the server refuses does not hold messages back")
    func aRefusedEntriesRecordHoldsNothingBack() async throws {
        let rig = try await rig()
        await rig.relay.refuse([.entries])
        try await rig.alice.send("the summary is enough", to: rig.room)
        try await settle([rig.alice, rig.bob], rig.mailbox)
        #expect(
            rig.bob.messages(in: rig.room).map(\.body).contains("the summary is enough"),
            "a refused entries record stopped a message that its summary already covered")
    }

    @Test("With only the summary saved, a reinstall still knows its place")
    func theSummaryAloneIsEnough() async throws {
        let rig = try await rig()
        await rig.relay.refuse([.entries])
        for index in 1...3 { try await rig.alice.send("summary only \(index)", to: rig.room) }
        try await settle([rig.alice, rig.bob], rig.mailbox)
        let feed = try feed(of: rig.alice, in: rig.room)
        let before = top(of: feed, in: rig.alice)
        let identity = try #require(rig.alice.enrolment?.identity)
        let stored = try await ownRecord(rig, of: feed.device, identity: identity)
        let entriesRecordTop = stored.flatMap(\.entries).filter { $0.feedKey == feed }.map(\.seq).max() ?? 0
        #expect(entriesRecordTop < before, "precondition: the entries record held Alice's last message")

        let again = await reinstall(rig)
        again.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await caughtUp(again)
        try await again.send("after, from the summary", to: rig.room)
        #expect(
            top(of: feed, in: again) == before + 1,
            "the reinstall took its place from the entries record, which was behind")
        try await settle([again, rig.bob], rig.mailbox)
        #expect(rig.bob.replica.forks.isEmpty)
    }

    @Test("The photo cleanup waits until the device has read its records")
    func theCleanupWaits() async throws {
        let rig = try await rig()
        let upload = AttachmentID()
        try await rig.mailbox.upload(
            OutgoingAttachment(id: upload, ciphertext: Data(count: 16), recipients: [RecipientTag(rawValue: Data(count: 16))]))
        rig.clock.advance(by: MailboxRules.sweepAge + 1)
        #expect(
            try await rig.mailbox.sweepableAttachments()[upload] != nil,
            "precondition: the upload is not old enough to be cleaned up")

        let again = await reinstall(rig)
        _ = try await again.sync(through: rig.mailbox, media: rig.mailbox)
        #expect(
            try await rig.mailbox.pendingAttachments()[upload] != nil,
            "a device that had not read its records deleted an upload its empty log does not name")
    }

    // MARK: What only the device kept

    @Test("Greetings, the room list's arrangement and read positions come back")
    func whatOnlyTheDeviceKeptComesBack() async throws {
        let rig = try await rig()
        let stamp = rig.alice.stamp()
        rig.alice.updateOrganisation {
            $0.rooms[rig.room] = RoomOrganisation(pin: Stamped(1.0, stamp: stamp))
        }
        rig.alice.persisted.greetedRooms.append(rig.room)
        let mark = try #require(rig.alice.replica.allEntries.first { $0.conversation == rig.room }?.hash)
        rig.alice.persisted.readThrough[rig.room] = mark
        _ = await rig.alice.publishOwnRecordsNow()

        let again = await reinstall(rig)
        again.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await caughtUp(again)
        #expect(again.organisation.rooms[rig.room] != nil, "the room list's arrangement was lost")
        #expect(again.persisted.greetedRooms.contains(rig.room), "every room will greet the member again")
        #expect(again.persisted.readThrough[rig.room] == mark, "every conversation will read as unread")
    }

    // MARK: Recovery onto a device whose key survived

    @Test("Recovering onto a device whose own key survived is that device, and it waits too")
    func recoveryOntoTheSameDevice() async throws {
        let rig = try await rig()
        try await rig.alice.send("before the recovery", to: rig.room)
        try await settle([rig.alice, rig.bob], rig.mailbox)
        let feed = try feed(of: rig.alice, in: rig.room)
        let before = top(of: feed, in: rig.alice)
        let key = try #require(rig.alice.recoveryKeyText())

        try await rig.keychain.remove(IdentityStore.identityKey)
        let again = await reinstall(rig)
        try await again.restore(fromRecoveryKey: key)
        #expect(again.enrolment?.device.id == feed.device, "the surviving key was not used")
        #expect(again.isCatchingUp, "a recovered device with its old key wrote before knowing its place")

        again.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await caughtUp(again)
        try await again.send("after the recovery", to: rig.room)
        #expect(top(of: feed, in: again) == before + 1)
        try await settle([again, rig.bob], rig.mailbox)
        #expect(rig.bob.replica.forks.isEmpty, "the recovered device forked its own log")
    }
}

@Suite("A device's standing is decided by its earliest certificate")
struct EarliestCertificateTests {
    @Test("Whatever order two certificates for one device arrive in, the earlier one decides")
    func theEarliestDecides() throws {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        let early = try DeviceCertificate.issue(
            for: device.publicKey, by: identity, at: Date(timeIntervalSince1970: 1_000))
        let late = try DeviceCertificate.issue(
            for: device.publicKey, by: identity, at: Date(timeIntervalSince1970: 9_000))

        for order in [[early, late], [late, early]] {
            var registry = DeviceRegistry(identity: identity.publicKeys)
            for certificate in order { try registry.admit(certificate) }
            #expect(
                registry.isAuthorized(device.id, at: Date(timeIntervalSince1970: 5_000)),
                "an entry written between the two certificates was refused")
            #expect(registry.standing(of: device.id)?.addedAt == early.issuedAt)
        }
    }
}

@Suite("The in-memory device sync fails the way CloudKit does")
struct TheDeviceSyncFakeTests {
    private func sealed(_ marker: UInt8, for identity: Identity, on device: DeviceID) throws -> DeviceRecords {
        let feed = SiblingFeed(
            entries: [], certificates: [], member: identity.id,
            positions: [.room(UUID()): EntryLink(seq: UInt64(marker), hash: EntryHash(rawValue: Data([marker])))])
        return try DeviceRecords.seal(feed, for: identity, on: device)
    }

    private actor Heard {
        var records: [SealedSiblingFeed] = []
        func add(_ record: SealedSiblingFeed) { records.append(record) }
    }

    @Test("A write over a copy it never read hands the server's copy over first, then lands")
    func aStaleWriteReadsTheServerCopy() async throws {
        let relay = InMemoryEntrySync.Relay(announces: false)
        let identity = Identity.generate()
        let device = DeviceKeys.generate().id
        let first = InMemoryEntrySync(relay: relay)
        _ = try await first.send(try sealed(1, for: identity, on: device), from: device)

        let second = InMemoryEntrySync(relay: relay)
        let heard = Heard()
        await second.onIncoming { record, _ in await heard.add(record) }
        let saved = try await second.send(try sealed(2, for: identity, on: device), from: device)

        #expect(saved.summary && saved.entries)
        #expect(await !heard.records.isEmpty, "the server's copy was written over without being read")
        let stored = try await second.ownRecords(of: device)
            .map { try $0.open(with: identity, from: device) }
        #expect(stored.allSatisfy { $0.positions.values.contains { $0.seq == 2 } })
    }

    @Test("A record over the size Apple documents is refused, and the summary still lands")
    func anOversizedRecordIsRefused() async throws {
        let relay = InMemoryEntrySync.Relay()
        let identity = Identity.generate()
        let device = DeviceKeys.generate().id
        let sync = InMemoryEntrySync(relay: relay)
        let big = SealedSiblingFeed(ciphertext: Data(count: EntrySyncRules.documentedRecordCeiling + 1))
        let saved = try await sync.send(
            DeviceRecords(summary: try sealed(1, for: identity, on: device).summary, entries: big),
            from: device)
        #expect(saved.summary)
        #expect(!saved.entries, "a record over a megabyte was accepted")
    }
}
