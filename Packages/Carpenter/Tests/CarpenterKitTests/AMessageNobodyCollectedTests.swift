@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A message nobody collected is never drawn as collected", .serialized)
struct AMessageNobodyCollectedTests {
    private let keychain = InMemoryKeychainStore()
    private let folder = TestScratch.root.appending(path: "carpenter-uncollected-\(UUID().uuidString)")

    private func joined() async throws -> (
        alice: AppSession, bob: AppSession, room: RoomID, mailbox: InMemoryMailbox, clock: TestClock
    ) {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let alice = TestSession.make(keychain: keychain, at: folder, clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lookout")
        let invite = try await alice.invite(
            joinerCode: await bob.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<5 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        try #require(alice.roster(of: room).members.count == 2, "precondition: Bob is in")
        return (alice, bob, room, mailbox, clock)
    }

    private func sentAndLeft(
        _ text: String, by alice: AppSession, in room: RoomID, through mailbox: InMemoryMailbox, clock: TestClock
    ) async throws -> MessageID {
        try await alice.send(text, to: room)
        try await alice.sync(through: mailbox)
        let message = try #require(alice.messages(in: room).last { $0.body == text })
        try #require(message.delivery == .sent, "precondition: the packet is waiting in Alice's iCloud")
        clock.advance(by: SyncSession.packetWaitsFor + 60)
        try await alice.sync(through: mailbox)
        return message.id
    }

    @Test("A packet withdrawn after the wait with no receipt leaves its message not collected")
    func anExpiredPacketIsNotDelivered() async throws {
        let (alice, bob, room, mailbox, clock) = try await joined()
        let message = try await sentAndLeft("are you there", by: alice, in: room, through: mailbox, clock: clock)

        let drawn = try #require(alice.messages(in: room).first { $0.id == message })
        #expect(
            drawn.delivery == .notCollected,
            "Bob's phone was off for the whole wait, and the bubble said \(drawn.delivery)")
        #expect(!drawn.delivery.isCollected)
        #expect(drawn.notGone?.wasTakenBack == true, "the orange circle did not say the copy was taken back")

        let bobID = try #require(bob.enrolment?.identity.id)
        let waiting = try #require(alice.waitingOn(in: room).first { $0.id == bobID })
        #expect(waiting.holding == .missing(1), "the waiting-on list said Bob has everything: \(waiting.holding)")
        #expect(waiting.takenBack == 1)
        #expect(alice.readBy(message, in: room).first { $0.id == bobID }?.collection == .notCollected)
    }

    @Test("A copy that reaches them later and is signed for moves the mark on to collected")
    func aLaterCopySignedForIsCollected() async throws {
        let (alice, bob, room, mailbox, clock) = try await joined()
        let message = try await sentAndLeft("again", by: alice, in: room, through: mailbox, clock: clock)
        alice.persisted.resend.insert(message.entry)
        try await alice.sync(through: mailbox)
        #expect(alice.messages(in: room).first { $0.id == message }?.delivery == .sent)

        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        let mark = try #require(alice.messages(in: room).first { $0.id == message }?.delivery)
        #expect(mark.isCollected, "Bob signed for the second copy and the bubble still said \(mark)")
        #expect(alice.readBy(message, in: room).allSatisfy { $0.collection != .notCollected })
    }

    @Test("Not collected survives a relaunch")
    func notCollectedIsWrittenDown() async throws {
        let (alice, _, room, mailbox, clock) = try await joined()
        let message = try await sentAndLeft("still there?", by: alice, in: room, through: mailbox, clock: clock)
        let reopened = TestSession.make(keychain: keychain, at: folder, clock: clock)
        await reopened.load()
        #expect(reopened.messages(in: room).first { $0.id == message }?.delivery == .notCollected)
    }

    @Test("A read receipt for a later message does not light a message that was never collected")
    func aLaterReceiptDoesNotCoverAnUncollectedMessage() async throws {
        let (alice, bob, room, mailbox, clock) = try await joined()
        await bob.setReportsDisplaying(true)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        let message = try await sentAndLeft("first", by: alice, in: room, through: mailbox, clock: clock)
        try await alice.send("second", to: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        let second = try #require(bob.messages(in: room).last { $0.body == "second" })
        await bob.markSeen(second.id, in: room)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try #require(
            alice.messages(in: room).last { $0.body == "second" }?.delivery.wasDisplayed == true,
            "precondition: Bob's phone reported the second message shown")

        #expect(
            alice.messages(in: room).first { $0.id == message }?.delivery == .notCollected,
            "Bob's receipt for the second message was taken as proof he was shown the first, which never reached him")
    }
}
