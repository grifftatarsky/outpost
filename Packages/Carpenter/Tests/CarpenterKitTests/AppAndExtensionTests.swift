@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("The app and the notification extension share one container without undoing each other", .serialized)
struct AppAndExtensionTests {
    private struct Rig {
        let alice: AppSession
        let app: AppSession
        let mailbox: InMemoryMailbox
        let room: RoomID
        let keychain: InMemoryKeychainStore
        let directory: URL
        let clock: TestClock
    }

    private func rig() async throws -> Rig {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "carpenter-two-processes-\(UUID().uuidString)")
        let alice = TestSession.make(clock: clock)
        let app = TestSession.make(keychain: keychain, at: directory, clock: clock)
        await alice.load()
        await app.load()
        try await alice.createIdentity(displayName: "Alice")
        try await app.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(app, into: room, of: alice, through: mailbox)
        return Rig(alice: alice, app: app, mailbox: mailbox, room: room, keychain: keychain, directory: directory, clock: clock)
    }

    private func extensionProcess(_ rig: Rig) async -> AppSession {
        let session = AppSession(
            storage: TestSession.storage(keychain: rig.keychain, at: rig.directory).readOnly,
            clock: rig.clock, denyList: .empty)
        await session.load()
        return session
    }

    private func relaunch(_ rig: Rig) async -> AppSession {
        let session = TestSession.make(keychain: rig.keychain, at: rig.directory, clock: rig.clock)
        await session.load()
        return session
    }

    @Test("A setting the app saves while the extension is running survives the extension's round")
    func aSettingSurvives() async throws {
        let rig = try await rig()
        let nse = await extensionProcess(rig)

        await rig.app.setMuted(true, for: rig.room)
        try await rig.alice.send("are you there", to: rig.room)
        try await rig.alice.sync(through: rig.mailbox)
        try await nse.sync(through: rig.mailbox, mode: .readOnly)
        try #require(nse.messages(in: rig.room).contains { $0.body == "are you there" }, "the extension never saw the message")

        let later = await relaunch(rig)
        #expect(later.isMuted(rig.room), "the extension's round wrote its older state over the app's")
    }

    @Test("A room the app deletes while the extension is running stays deleted")
    func aDeletionSurvives() async throws {
        let rig = try await rig()
        let bob = try #require(rig.app.enrolment?.identity.id)
        try await rig.alice.remove(bob, from: rig.room)
        for _ in 0..<3 {
            try await rig.alice.sync(through: rig.mailbox)
            try await rig.app.sync(through: rig.mailbox)
        }
        let nse = await extensionProcess(rig)

        try await rig.app.deleteRoom(rig.room)
        try await nse.sync(through: rig.mailbox, mode: .readOnly)

        let later = await relaunch(rig)
        #expect(later.replica.closedRooms.contains(rig.room), "the extension's round forgot the deletion")
        #expect(!later.rooms.contains { $0.id == rig.room })
        #expect(later.replica.gaps().isEmpty, "the deleted room's numbers read as missing again")
    }

    @Test("The extension writes nothing to the files it shares with the app")
    func theExtensionWritesNothing() async throws {
        let rig = try await rig()
        let files = ["log.carpenter", "state.json"].map { rig.directory.appending(path: $0) }
        let before = try files.map { try Data(contentsOf: $0) }
        let keysBefore = await rig.keychain.synchronizedItems

        let nse = await extensionProcess(rig)
        try await rig.alice.send("are you there", to: rig.room)
        try await rig.alice.sync(through: rig.mailbox)
        try await nse.sync(through: rig.mailbox, mode: .readOnly)

        #expect(try files.map { try Data(contentsOf: $0) } == before, "the extension wrote to a shared file")
        #expect(await rig.keychain.synchronizedItems == keysBefore)
    }

    @Test("The extension finds a message in its own round, and a reload finds one the app wrote")
    func theExtensionFindsTheMessageEitherWay() async throws {
        let rig = try await rig()
        let nse = await extensionProcess(rig)
        let before = nse.latestIncomingMessage()?.id

        try await rig.alice.send("from the round", to: rig.room)
        try await rig.alice.sync(through: rig.mailbox)
        try await nse.sync(through: rig.mailbox, mode: .readOnly)
        #expect(nse.latestIncomingMessage()?.id != before, "the round collected the message and the extension did not see it")

        try await rig.alice.send("from the app", to: rig.room)
        try await rig.alice.sync(through: rig.mailbox)
        try await rig.app.sync(through: rig.mailbox)
        await nse.load()
        #expect(nse.messages(in: rig.room).contains { $0.body == "from the app" }, "a reload did not pick up what the app wrote")
    }

    @Test("What the extension collects is still collected by the app, and nothing is lost between them")
    func nothingIsLostBetweenThem() async throws {
        let rig = try await rig()
        let nse = await extensionProcess(rig)

        try await rig.alice.send("first", to: rig.room)
        try await rig.alice.sync(through: rig.mailbox)
        try await nse.sync(through: rig.mailbox, mode: .readOnly)
        try await rig.app.sync(through: rig.mailbox)

        let later = await relaunch(rig)
        #expect(later.messages(in: rig.room).contains { $0.body == "first" })
        #expect(later.integrity.unverifiableOnDisk == 0, "the extension left entries on disk the app could not verify")
        #expect(try await rig.mailbox.pendingDeliveries().isEmpty, "a packet was left offered for ever")
    }
}
