@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Editing and withdrawing")
struct EditingAndWithdrawingTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func author() -> Author { Author(chain: EpochChain.create(room: ConversationID.room(UUID())).chain) }

    private func folded(_ entries: [Entry], _ chain: EpochChain) -> [RenderedEntry] {
        Fold.render(entries, using: chain)
    }

    // MARK: The windows

    @Test("An edit inside fifteen minutes replaces the words, and says it was edited")
    func editInsideTheWindow() throws {
        var alice = author()
        let post = try alice.post("frist", at: start)
        let edit = try alice.append(
            try Payload.edit(post.hash, to: "first"), at: start.addingTimeInterval(600))

        let drawn = try #require(folded([post, edit], alice.chain).first { $0.id == post.hash })
        guard case .text(let body) = drawn.content else {
            Issue.record("the edit did not take")
            return
        }
        #expect(body == "first")
        #expect(drawn.isEdited, "the room was not told the words changed")
    }

    @Test("An edit after fifteen minutes is ignored by every device")
    func editOutsideTheWindow() throws {
        var alice = author()
        let post = try alice.post("frist", at: start)
        let late = try alice.append(
            try Payload.edit(post.hash, to: "rewritten much later"),
            at: start.addingTimeInterval(Editing.editWindow + 1))

        let drawn = try #require(folded([post, late], alice.chain).first { $0.id == post.hash })
        guard case .text(let body) = drawn.content else {
            Issue.record("the message stopped being text")
            return
        }
        #expect(body == "frist", "an edit outside the window rewrote the message")
        #expect(!drawn.isEdited)
    }

    @Test("A withdrawal inside two minutes takes the words back")
    func withdrawInsideTheWindow() throws {
        var alice = author()
        let post = try alice.post("said too fast", at: start)
        let gone = try alice.append(
            try Payload.tombstone(post.hash), at: start.addingTimeInterval(60))

        let drawn = try #require(folded([post, gone], alice.chain).first { $0.id == post.hash })
        guard case .withdrawn = drawn.content else {
            Issue.record("the withdrawal did not take")
            return
        }
    }

    @Test("A withdrawal after two minutes is ignored")
    func withdrawOutsideTheWindow() throws {
        var alice = author()
        let post = try alice.post("said too fast", at: start)
        let late = try alice.append(
            try Payload.tombstone(post.hash),
            at: start.addingTimeInterval(Editing.withdrawWindow + 1))

        let drawn = try #require(folded([post, late], alice.chain).first { $0.id == post.hash })
        guard case .text = drawn.content else {
            Issue.record("a withdrawal outside the window still took the message back")
            return
        }
    }

    @Test("The two windows are not the same length")
    func theWindowsDiffer() throws {
        #expect(Editing.editWindow == 15 * 60)
        #expect(Editing.withdrawWindow == 2 * 60)

        var alice = author()
        let post = try alice.post("both", at: start)
        let atFive = start.addingTimeInterval(300)
        #expect(Editing.isOpen(at: atFive, for: start, within: Editing.editWindow))
        #expect(!Editing.isOpen(at: atFive, for: start, within: Editing.withdrawWindow))

        let edit = try alice.append(try Payload.edit(post.hash, to: "edited"), at: atFive)
        let gone = try alice.append(try Payload.tombstone(post.hash), at: atFive)
        let drawn = try #require(folded([post, edit, gone], alice.chain).first { $0.id == post.hash })
        guard case .text(let body) = drawn.content else {
            Issue.record("the late withdrawal took effect")
            return
        }
        #expect(body == "edited")
    }

    @Test("An edit stamped before its own message is refused")
    func backdatedEditIsRefused() throws {
        #expect(!Editing.isOpen(at: start.addingTimeInterval(-1), for: start, within: Editing.editWindow))
    }

    // MARK: Whose message it is

    @Test("Only the author may rewrite or withdraw their own words")
    func onlyTheAuthor() throws {
        var alice = author()
        var mallory = Author(chain: alice.chain)
        let post = try alice.post("alice said this", at: start)

        let forgedEdit = try mallory.append(
            try Payload.edit(post.hash, to: "mallory said this"), at: start.addingTimeInterval(10))
        let forgedWithdraw = try mallory.append(
            try Payload.tombstone(post.hash), at: start.addingTimeInterval(20))

        let drawn = try #require(
            folded([post, forgedEdit, forgedWithdraw], alice.chain).first { $0.id == post.hash })
        guard case .text(let body) = drawn.content else {
            Issue.record("somebody withdrew a message that was not theirs")
            return
        }
        #expect(body == "alice said this", "somebody rewrote a message that was not theirs")
    }

    // MARK: What survives

    @Test("A withdrawn message is still an entry, not a hole")
    func withdrawingKeepsTheEntry() throws {
        var alice = author()
        let post = try alice.post("taken back", at: start)
        let gone = try alice.append(try Payload.tombstone(post.hash), at: start.addingTimeInterval(30))

        let all = folded([post, gone], alice.chain)
        let drawn = try #require(all.first { $0.id == post.hash })
        #expect(drawn.author == alice.identity.id, "the entry lost its author")
        #expect(drawn.wallTime == start, "the entry lost its place in time")
        #expect(all.contains { $0.id == post.hash }, "the fold dropped the entry rather than drawing a placeholder")
    }

    @Test("A withdrawn message cannot then be edited back into existence")
    func withdrawalIsTerminal() throws {
        var alice = author()
        let post = try alice.post("gone", at: start)
        let gone = try alice.append(try Payload.tombstone(post.hash), at: start.addingTimeInterval(10))
        let after = try alice.append(
            try Payload.edit(post.hash, to: "back again"), at: start.addingTimeInterval(20))

        let drawn = try #require(folded([post, gone, after], alice.chain).first { $0.id == post.hash })
        guard case .withdrawn = drawn.content else {
            Issue.record("an edit undid a withdrawal")
            return
        }
    }

    // MARK: The history

    @Test("Every wording is kept, oldest first, so \"edited\" can be checked")
    func revisionsAreKept() throws {
        var alice = author()
        let post = try alice.post("one", at: start)
        let first = try alice.append(
            try Payload.edit(post.hash, to: "two"), at: start.addingTimeInterval(60))
        let second = try alice.append(
            try Payload.edit(post.hash, to: "three"), at: start.addingTimeInterval(120))

        let drawn = try #require(
            folded([post, first, second], alice.chain).first { $0.id == post.hash })
        #expect(drawn.revisions.map(\.text) == ["one", "two", "three"])
        #expect(drawn.revisions.map(\.at) == [start, start.addingTimeInterval(60), start.addingTimeInterval(120)])
    }

    @Test("A message nobody edited carries no history at all")
    func noHistoryWhenUnedited() throws {
        var alice = author()
        let post = try alice.post("said once", at: start)
        let drawn = try #require(folded([post], alice.chain).first { $0.id == post.hash })
        #expect(drawn.revisions.isEmpty)
        #expect(!drawn.isEdited)
    }

    @Test("Withdrawing drops the wordings with the words")
    func withdrawalClearsTheHistory() throws {
        var alice = author()
        let post = try alice.post("one", at: start)
        let edit = try alice.append(
            try Payload.edit(post.hash, to: "two"), at: start.addingTimeInterval(30))
        let gone = try alice.append(
            try Payload.tombstone(post.hash), at: start.addingTimeInterval(60))

        let drawn = try #require(folded([post, edit, gone], alice.chain).first { $0.id == post.hash })
        #expect(drawn.revisions.isEmpty, "the room could still read what was withdrawn")
    }
}

@MainActor
@Suite("Editing and withdrawing, through the session", .serialized)
struct SessionEditingTests {
    private func room() async throws -> (session: AppSession, room: ConversationID, clock: TestClock) {
        let clock = TestClock(now: TestSession.now)
        let session = AppSession(storage: TestSession.storage(), clock: clock)
        await session.load()
        try await session.createIdentity(displayName: "Alice")
        let room = try await session.createRoom(named: "Hangar 7")
        return (session, room, clock)
    }

    @Test("Editing your own message inside the window rewrites it for the room")
    func editWorks() async throws {
        let (session, room, _) = try await room()
        try await session.send("frist", to: room)
        let message = try #require(session.messages(in: room).last)

        try await session.edit(message.id, to: "first")

        let after = try #require(session.messages(in: room).last)
        #expect(after.body == "first")
        #expect(after.isEdited)
        #expect(after.revisions.map(\.text) == ["frist", "first"])
    }

    @Test("Withdrawing takes the words back and leaves the message in place")
    func withdrawWorks() async throws {
        let (session, room, _) = try await room()
        try await session.send("said too fast", to: room)
        let message = try #require(session.messages(in: room).last)

        try await session.withdraw(message.id)

        let after = try #require(session.messages(in: room).last)
        #expect(after.isWithdrawn)
        #expect(
            session.messages(in: room).count == 1,
            "withdrawing removed the message rather than taking its words back")
        #expect(after.revisions.isEmpty)
    }

    @Test("The session refuses an edit once the fifteen minutes are up")
    func editWindowIsEnforced() async throws {
        let (session, room, clock) = try await room()
        try await session.send("frist", to: room)
        let message = try #require(session.messages(in: room).last)

        clock.advance(by: Editing.editWindow + 1)

        await #expect(throws: AppSessionError.tooLateToEdit) {
            try await session.edit(message.id, to: "too late")
        }
        #expect(session.messages(in: room).last?.body == "frist")
    }

    @Test("The session refuses a withdrawal once the two minutes are up")
    func withdrawWindowIsEnforced() async throws {
        let (session, room, clock) = try await room()
        try await session.send("said too fast", to: room)
        let message = try #require(session.messages(in: room).last)

        clock.advance(by: Editing.withdrawWindow + 1)

        await #expect(throws: AppSessionError.tooLateToWithdraw) {
            try await session.withdraw(message.id)
        }
        #expect(session.messages(in: room).last?.isWithdrawn == false)
    }

    @Test("How long is left runs out, and the two windows run out at different times")
    func timeLeftTracksTheWindows() async throws {
        let (session, room, clock) = try await room()
        try await session.send("both", to: room)
        let message = try #require(session.messages(in: room).last)

        #expect(session.timeLeft(toEdit: message.id) != nil)
        #expect(session.timeLeft(toWithdraw: message.id) != nil)

        clock.advance(by: 300)
        #expect(session.timeLeft(toEdit: message.id) != nil)
        #expect(
            session.timeLeft(toWithdraw: message.id) == nil,
            "withdrawing was still offered after its window closed")

        clock.advance(by: Editing.editWindow)
        #expect(session.timeLeft(toEdit: message.id) == nil)
    }

    @Test("A withdrawn message offers neither act")
    func withdrawnOffersNothing() async throws {
        let (session, room, _) = try await room()
        try await session.send("gone", to: room)
        let message = try #require(session.messages(in: room).last)
        try await session.withdraw(message.id)

        #expect(session.timeLeft(toEdit: message.id) == nil)
        #expect(session.timeLeft(toWithdraw: message.id) == nil)
    }

    @Test("Somebody else's message is not this member's to change")
    func notYourMessage() async throws {
        let mailbox = InMemoryMailbox()
        let (alice, room, _) = try await room()
        let bob = TestSession.make()
        await bob.load()
        try await bob.createIdentity(displayName: "Bob")

        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))

        try await alice.send("mine", to: room)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        let message = try #require(alice.messages(in: room).last)
        #expect(
            bob.messages(in: room).contains { $0.id == message.id },
            "precondition: Bob holds Alice's message")
        #expect(bob.timeLeft(toEdit: message.id) == nil)
        #expect(bob.timeLeft(toWithdraw: message.id) == nil)
        await #expect(throws: AppSessionError.notYourMessage) {
            try await bob.edit(message.id, to: "not yours")
        }
        await #expect(throws: AppSessionError.notYourMessage) { try await bob.withdraw(message.id) }
        #expect(alice.messages(in: room).last?.body == "mine")
    }

    @Test("An empty edit is refused rather than treated as taking it back")
    func emptyEditIsNotAWithdrawal() async throws {
        let (session, room, _) = try await room()
        try await session.send("still here", to: room)
        let message = try #require(session.messages(in: room).last)

        await #expect(throws: AppSessionError.nothingToSay) {
            try await session.edit(message.id, to: "   ")
        }
        #expect(session.messages(in: room).last?.isWithdrawn == false)
    }
}
