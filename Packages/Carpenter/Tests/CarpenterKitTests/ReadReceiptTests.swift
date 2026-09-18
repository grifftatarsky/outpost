import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Delivered and read", .serialized)
@MainActor
struct ReadReceiptTests {
    private func scratch() -> URL {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-read-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func session(_ clock: TestClock) -> AppSession {
        let directory = scratch()
        return AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(),
                log: FileLogStore(url: directory.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json"))
            ),
            clock: clock
        )
    }

    private func pair(
        _ clock: TestClock, _ mailbox: InMemoryMailbox
    ) async throws -> (alice: AppSession, bob: AppSession, room: RoomID) {
        let alice = session(clock)
        let bob = session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, room)
    }

    private func state(_ session: AppSession, _ room: RoomID, _ body: String) -> DeliveryState? {
        session.messages(in: room).first { $0.body == body }?.delivery
    }

    private func newest(_ session: AppSession, _ room: RoomID) -> MessageID {
        session.messages(in: room).last { !$0.isMine }?.id
            ?? MessageID(entry: EntryHash(rawValue: Data()))
    }

    @Test("A message goes pending, sent, delivered, shown")
    func theWholeProgression() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob, room) = try await pair(clock, mailbox)

        await bob.setReportsDisplaying(true)
        for _ in 0..<4 {
            try await bob.sync(through: mailbox)
            try await alice.sync(through: mailbox)
        }

        try await alice.send("are you there", to: room)
        #expect(state(alice, room, "are you there") == .pending, "a message still here wore a mark")

        try await alice.sync(through: mailbox)
        #expect(
            state(alice, room, "are you there") == .sent,
            "nobody had collected it yet and the first orb was already lit")

        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        #expect(state(alice, room, "are you there") == .delivered)
        #expect(
            state(alice, room, "are you there")?.wasDisplayed == false,
            "collecting a message was mistaken for showing it")

        await bob.markSeen(newest(bob, room), in: room)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        #expect(state(alice, room, "are you there")?.wasDisplayed == true, "the receipt never arrived")
        #expect(state(alice, room, "are you there")?.displayedAt != nil)
    }

    @Test("A member who does not report is said so, not left at delivered")
    func withoutOptingInReadsAsNotReported() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob, room) = try await pair(clock, mailbox)

        try await alice.send("did you see this", to: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        #expect(state(alice, room, "did you see this") == .notReported)
    }

    @Test("Your own reading never lights your own second orb")
    func ownReadingDoesNotCount() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob, room) = try await pair(clock, mailbox)

        try await alice.send("talking to myself", to: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        await alice.setReportsDisplaying(true)
        await alice.markSeen(newest(alice, room), in: room)
        try await alice.sync(through: mailbox)

        #expect(state(alice, room, "talking to myself")?.wasDisplayed == false)
    }

    @Test("Seeing the same message twice writes nothing")
    func receiptsDoNotRepeat() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob, room) = try await pair(clock, mailbox)

        try await alice.send("one thing", to: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        await bob.setReportsDisplaying(true)
        await bob.markSeen(newest(bob, room), in: room)
        try await bob.sync(through: mailbox)

        let before = bob.entryCount
        await bob.markSeen(newest(bob, room), in: room)
        await bob.markSeen(newest(bob, room), in: room)
        #expect(bob.entryCount == before, "glancing at a room wrote a receipt every time")
    }

    @Test("Opening a room does not mark the backlog read")
    func openingIsNotReading() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob, room) = try await pair(clock, mailbox)

        await bob.setReportsDisplaying(true)
        for _ in 0..<4 {
            try await bob.sync(through: mailbox)
            try await alice.sync(through: mailbox)
        }

        try await alice.send("older", to: room)
        try await alice.send("newer", to: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        let older = try #require(bob.messages(in: room).first { $0.body == "older" })
        await bob.markSeen(older.id, in: room)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        #expect(state(alice, room, "older")?.wasDisplayed == true)
        #expect(
            state(alice, room, "newer")?.wasDisplayed == false,
            "a message that never came into view was reported as read")
    }

    @Test("Turning reporting off tells the room")
    func optingOutIsPublished() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob, room) = try await pair(clock, mailbox)

        await bob.setReportsDisplaying(true)
        for _ in 0..<4 {
            try await bob.sync(through: mailbox)
            try await alice.sync(through: mailbox)
        }

        try await alice.send("first", to: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        #expect(state(alice, room, "first") == .delivered, "precondition: Bob was reporting")

        await bob.setReportsDisplaying(false)
        for _ in 0..<4 {
            try await bob.sync(through: mailbox)
            try await alice.sync(through: mailbox)
        }

        #expect(
            state(alice, room, "first") == .notReported,
            "Alice was left waiting on a mark Bob had stopped sending")
    }

    @Test("A receipt never appears in the transcript")
    func receiptsAreNotMessages() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob, room) = try await pair(clock, mailbox)

        try await alice.send("hello", to: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        await bob.setReportsDisplaying(true)
        await bob.markSeen(newest(bob, room), in: room)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        #expect(alice.messages(in: room).count == 1, "a receipt or a policy was drawn as a message")
        #expect(bob.messages(in: room).count == 1)
    }
}
