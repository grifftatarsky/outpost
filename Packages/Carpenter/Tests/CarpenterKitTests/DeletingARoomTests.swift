@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

private actor LogThatWillNotRewrite: LogStore {
    private let real: FileLogStore
    private var refusing = true

    init(url: URL) { real = FileLogStore(url: url) }

    func append(_ entries: [Entry]) async throws { try await real.append(entries) }
    func loadAll() async throws -> LoadedLog { try await real.loadAll() }
    func removeAll() async throws { try await real.removeAll() }
    func removeEntries(where shouldRemove: @escaping @Sendable (Entry) -> Bool) async throws -> Int {
        if refusing { throw CocoaError(.fileWriteNoPermission) }
        return try await real.removeEntries(where: shouldRemove)
    }
}

@MainActor
@Suite("Deleting a conversation you are no longer in", .serialized)
struct DeletingARoomTests {
    private struct Rig {
        let alice: AppSession
        let bob: AppSession
        let mailbox: InMemoryMailbox
        let hangar: ConversationID
        let kitchen: ConversationID
        let bobID: ParticipantID
        let keychain: InMemoryKeychainStore
        let directory: URL
        let media: MemoryMediaStore
        let clock: TestClock
    }

    private func rig() async throws -> Rig {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "carpenter-delete-\(UUID().uuidString)")
        let media = MemoryMediaStore()
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(keychain: keychain, at: directory, media: media, clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let hangar = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: hangar, of: alice, through: mailbox, media: mailbox)
        let kitchen = try await alice.createRoom(named: "Kitchen")
        try await join(bob, into: kitchen, of: alice, through: mailbox, media: mailbox)

        try await alice.send("the hangar doors stick", to: hangar)
        try await bob.send("I will bring oil", to: hangar)
        try await alice.send("kettle is on", to: kitchen)
        try await rounds(alice, bob, mailbox)

        let bobID = try #require(bob.enrolment?.identity.id)
        return Rig(
            alice: alice, bob: bob, mailbox: mailbox, hangar: hangar, kitchen: kitchen, bobID: bobID,
            keychain: keychain, directory: directory, media: media, clock: clock)
    }

    private func rounds(_ sessions: AppSession..., through mailbox: InMemoryMailbox, count: Int = 3)
        async throws
    {
        for _ in 0..<count {
            for session in sessions { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func rounds(_ alice: AppSession, _ bob: AppSession, _ mailbox: InMemoryMailbox) async throws {
        try await rounds(alice, bob, through: mailbox)
    }

    private func removed(_ rig: Rig) async throws {
        try await rig.alice.remove(rig.bobID, from: rig.hangar)
        try await rounds(rig.alice, rig.bob, rig.mailbox)
        try #require(rig.bob.standing(in: rig.hangar) != .present)
    }

    @Test("A conversation you are still in cannot be deleted, and nothing is taken")
    func stillInCannotDelete() async throws {
        let rig = try await rig()

        #expect(rig.bob.deletion(of: rig.hangar) == .stillIn)
        await #expect(throws: MembershipError.stillInTheRoom) {
            try await rig.bob.deleteRoom(rig.hangar)
        }
        #expect(rig.bob.messages(in: rig.hangar).count == 2)
    }

    @Test("Deleting after a removal takes every message, the key and the room, and leaves the rest")
    func deletingTakesEverything() async throws {
        let rig = try await rig()
        try await removed(rig)
        let epochs = try #require(rig.bob.persisted.epochs[rig.hangar])

        try await rig.bob.deleteRoom(rig.hangar)

        #expect(!rig.bob.rooms.contains { $0.id == rig.hangar }, "the room is still listed")
        #expect(rig.bob.messages(in: rig.hangar).isEmpty)
        #expect(rig.bob.replica.entries(in: rig.hangar).isEmpty)
        let onDisk = try await rig.bob.storage.log.loadAll().entries
        #expect(!onDisk.contains { $0.conversation == rig.hangar }, "the log on disk still holds the room")
        for raw in epochs {
            #expect(
                try await rig.keychain.data(for: AppSession.epochKey(rig.hangar, EpochNumber(rawValue: raw)))
                    == nil,
                "a key that opens the deleted room is still in the keychain")
        }
        #expect(!rig.bob.persisted.knownRooms.contains(rig.hangar))
        #expect(rig.bob.chains[rig.hangar] == nil)
        #expect(rig.bob.awaitingAdmission.isEmpty, "the old invitation came back as waiting to be let in")

        #expect(rig.bob.messages(in: rig.kitchen).map(\.body) == ["kettle is on"])
        #expect(rig.bob.missingHistory(in: rig.kitchen).isEmpty, "the deleted room left holes in Alice's feed")
    }

    @Test("A relaunch does not bring it back, and repair does not ask for it")
    func aRelaunchDoesNotBringItBack() async throws {
        let rig = try await rig()
        try await removed(rig)
        try await rig.bob.deleteRoom(rig.hangar)

        let relaunched = TestSession.make(
            keychain: rig.keychain, at: rig.directory, media: rig.media, clock: rig.clock)
        await relaunched.load()
        try await rounds(rig.alice, relaunched, rig.mailbox)
        rig.clock.advance(by: AppSession.automaticRepairInterval + AppSession.holeSettlingDelay + 60)
        try await rounds(rig.alice, relaunched, rig.mailbox)

        #expect(!relaunched.rooms.contains { $0.id == rig.hangar })
        #expect(relaunched.replica.entries(in: rig.hangar).isEmpty)
        #expect(relaunched.replica.gaps().isEmpty, "the relaunch read the deleted room as missing")
        #expect(relaunched.rooms.contains { $0.id == rig.kitchen })
        try await relaunched.send("still here", to: rig.kitchen)
        try await rounds(rig.alice, relaunched, rig.mailbox)
        #expect(
            rig.alice.messages(in: rig.kitchen).last?.body == "still here",
            "a message after a relaunch reused a spent number and did not arrive")
        #expect(rig.alice.forks.isEmpty)
    }

    @Test("Something said before the removal that arrives after the deletion is not kept")
    func aLateArrivalIsNotKept() async throws {
        let rig = try await rig()
        let carol = TestSession.make(clock: rig.clock)
        await carol.load()
        try await carol.createIdentity(displayName: "Carol")
        try await join(carol, into: rig.hangar, of: rig.alice, through: rig.mailbox)
        try await join(carol, into: rig.kitchen, of: rig.alice, through: rig.mailbox)
        try await rounds(rig.alice, rig.bob, carol, through: rig.mailbox)
        try #require(rig.bob.roster(of: rig.hangar).members.contains(try #require(carol.enrolment?.identity.id)))

        try await carol.send("sorry, late to this", to: rig.hangar)
        try await removed(rig)
        try await rig.bob.deleteRoom(rig.hangar)

        try await carol.sync(through: rig.mailbox)
        let arrived = try await rig.bob.sync(through: rig.mailbox)
        try #require(arrived.entriesDelivered > 0, "Carol's message never reached Bob, so this proves nothing")

        #expect(!rig.bob.rooms.contains { $0.id == rig.hangar }, "a late message brought the room back")
        #expect(rig.bob.replica.entries(in: rig.hangar).isEmpty)
        #expect(rig.bob.replica.gaps().isEmpty)
        #expect(!(try await rig.bob.storage.log.loadAll().entries.contains { $0.conversation == rig.hangar }))
    }

    @Test("Leaving and deleting at once waits for the leaving to be sent")
    func leavingIsSentFirst() async throws {
        let rig = try await rig()
        try await rig.bob.leave(rig.hangar)

        #expect(rig.bob.deletion(of: rig.hangar) == .departureNotSent)
        await #expect(throws: MembershipError.departureNotSent) {
            try await rig.bob.deleteRoom(rig.hangar)
        }

        try await rig.bob.sync(through: rig.mailbox)
        #expect(rig.bob.deletion(of: rig.hangar) == .allowed)
        try await rig.bob.deleteRoom(rig.hangar)
        try await rig.alice.sync(through: rig.mailbox)
        #expect(
            rig.alice.roster(of: rig.hangar).departure(of: rig.bobID) != nil,
            "the room never heard that Bob left")
    }

    @Test("A key sent by somebody who had not heard yet is refused")
    func aLateKeyIsRefused() async throws {
        let rig = try await rig()
        try await rig.bob.leave(rig.hangar)
        try await rig.bob.sync(through: rig.mailbox)
        try await rig.bob.deleteRoom(rig.hangar)

        try await rig.alice.advanceEpoch(of: rig.hangar)
        let sent = try await rig.alice.sync(through: rig.mailbox)
        try #require(sent.packetsWritten > 0, "Alice sent nothing, so this proves nothing")
        let arrived = try await rig.bob.sync(through: rig.mailbox)
        try #require(!arrived.grantsReceived.isEmpty, "no key reached Bob, so this proves nothing")

        #expect(rig.bob.chains[rig.hangar] == nil, "a key for the deleted room was installed")
        #expect(!rig.bob.persisted.knownRooms.contains(rig.hangar))
        #expect(!rig.bob.rooms.contains { $0.id == rig.hangar })
    }

    @Test("Photos in the room go from this device; one this member sent stays for the people owed it")
    func photos() async throws {
        let rig = try await rig()
        try await rig.alice.send(SendingPhotoTests.photo(), to: rig.hangar, through: rig.mailbox)
        try await rig.bob.send(SendingPhotoTests.photo(), to: rig.hangar, through: rig.mailbox)
        try await rig.alice.sync(through: rig.mailbox)
        try await rig.bob.sync(through: rig.mailbox, media: rig.mailbox)
        let hers = try #require(rig.bob.messages(in: rig.hangar).last { !$0.isMine && $0.media != nil }?.media?.id)
        let his = try #require(rig.bob.messages(in: rig.hangar).last { $0.isMine && $0.media != nil }?.media?.id)
        try #require(await rig.media.sealed(for: hers) != nil)

        try await rig.alice.remove(rig.bobID, from: rig.hangar)
        try await rig.alice.sync(through: rig.mailbox)
        try await rig.bob.sync(through: rig.mailbox)
        try #require(rig.bob.standing(in: rig.hangar) != .present)
        try #require(try await rig.mailbox.pendingAttachments()[his] != nil, "Alice collected it, so this proves nothing")
        try await rig.bob.deleteRoom(rig.hangar)

        #expect(await rig.media.sealed(for: hers) == nil, "a photo from the deleted room is still on this device")

        rig.clock.advance(by: MailboxRules.sweepAge + 60)
        let relaunched = TestSession.make(
            keychain: rig.keychain, at: rig.directory, media: rig.media, clock: rig.clock)
        await relaunched.load()
        try await relaunched.sync(through: rig.mailbox, media: rig.mailbox)
        #expect(
            try await rig.mailbox.pendingAttachments()[his] != nil,
            "deleting took back a photo other people had not collected yet")
    }

    @Test("A deletion cut off before the log was rewritten is finished on the next launch")
    func aCutOffDeletionIsFinished() async throws {
        let rig = try await rig()
        try await removed(rig)
        let logURL = rig.directory.appending(path: "log.carpenter")

        let refusing = AppSession(
            storage: SessionStorage(
                keychain: rig.keychain, log: LogThatWillNotRewrite(url: logURL),
                documents: FileDocumentStore(url: rig.directory.appending(path: "state.json")),
                media: rig.media),
            clock: rig.clock, denyList: .empty)
        await refusing.load()
        try await refusing.deleteRoom(rig.hangar)
        #expect(
            try await FileLogStore(url: logURL).loadAll().entries.contains { $0.conversation == rig.hangar },
            "the refusing log did not refuse, so this test proves nothing")

        let relaunched = TestSession.make(
            keychain: rig.keychain, at: rig.directory, media: rig.media, clock: rig.clock)
        await relaunched.load()

        #expect(!relaunched.rooms.contains { $0.id == rig.hangar }, "the half-deleted room came back")
        #expect(!(try await FileLogStore(url: logURL).loadAll().entries.contains { $0.conversation == rig.hangar }))
        #expect(relaunched.replica.gaps().isEmpty)
    }

    @Test("Being invited back after deleting lets them in again")
    func invitedBack() async throws {
        let rig = try await rig()
        try await removed(rig)
        try await rig.bob.deleteRoom(rig.hangar)

        try await join(rig.bob, into: rig.hangar, of: rig.alice, through: rig.mailbox, rounds: 6)

        #expect(rig.bob.standing(in: rig.hangar) == .present)
        #expect(rig.bob.rooms.contains { $0.id == rig.hangar }, "the room did not come back on rejoining")
        try await rig.bob.send("back again", to: rig.hangar)
        try await rounds(rig.alice, rig.bob, rig.mailbox)
        #expect(rig.alice.messages(in: rig.hangar).last?.body == "back again")
    }

    @Test("An Outpost is not a conversation that can be deleted")
    func outpostsAreNotDeletable() async throws {
        let rig = try await rig()
        #expect(rig.bob.deletion(of: ConversationID.outpost(of: rig.bobID)) == .stillIn)
        #expect(rig.bob.deletion(of: ConversationID.outpost(of: try #require(rig.alice.enrolment?.identity.id))) == .stillIn)
    }

    @Test("Deleting on one device deletes on the member's other device, and the key does not come back")
    func followsTheMember() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let relay = InMemoryEntrySync.Relay(announces: false)
        let keychain = InMemoryKeychainStore()

        let alice = TestSession.make(clock: clock)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")

        let first = TestSession.make(keychain: keychain, clock: clock)
        first.syncDevices(through: InMemoryEntrySync(relay: relay))
        await first.load()
        try await first.createIdentity(displayName: "Bob")

        let hangar = try await alice.createRoom(named: "Hangar 7")
        try await join(first, into: hangar, of: alice, through: mailbox)
        try await first.send("hello from the first phone", to: hangar)

        try await keychain.remove(IdentityStore.deviceKey)
        let second = TestSession.make(keychain: keychain, clock: clock)
        second.syncDevices(through: InMemoryEntrySync(relay: relay))
        await second.load()

        try await settle(first, second) { second.chains[hangar] != nil }
        try #require(second.chains[hangar] != nil, "the second device never received the room's key")
        second.sendOwnEntries()
        try await Task.sleep(for: .milliseconds(200))

        try await alice.remove(try #require(first.enrolment?.identity.id), from: hangar)
        try await rounds(alice, first, mailbox)
        try await first.deleteRoom(hangar)
        await first.refreshDeviceSync()
        #expect(
            first.chains[hangar] == nil,
            "the other device's feed, written before the deletion, handed the key straight back")

        try await settle(first, second) { second.chains[hangar] == nil }

        #expect(second.chains[hangar] == nil, "the other device still holds the deleted room's key")
        #expect(second.replica.closedRooms.contains(hangar))
        #expect(second.replica.entries(in: hangar).isEmpty)
        #expect(first.chains[hangar] == nil, "the other device's feed handed the key back")
        #expect(!first.persisted.knownRooms.contains(hangar))
    }

    private func settle(_ first: AppSession, _ second: AppSession, until done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !done(), Date() < deadline {
            await first.refreshDeviceSync()
            await second.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
        for _ in 0..<4 {
            await first.refreshDeviceSync()
            await second.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
}
