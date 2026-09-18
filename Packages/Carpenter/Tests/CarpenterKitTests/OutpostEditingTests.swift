import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("Changing your own post", .serialized)
struct OutpostEditingTests {
    private func member() async throws -> (AppSession, TestClock) {
        let clock = TestClock(now: TestSession.now)
        let alice = AppSession(storage: TestSession.storage(), clock: clock)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        return (alice, clock)
    }

    @Test("A post can be rewritten, and every copy is told that it was")
    func rewriting() async throws {
        let (alice, _) = try await member()
        try await alice.send("teh wrong word", to: nil)
        let post = try #require(alice.feed().first)
        #expect(post.editedAt == nil)

        try await alice.edit(post.id, to: "the right word")

        let after = try #require(alice.feed().first)
        #expect(after.body == "the right word")
        #expect(after.editedAt != nil, "the post did not carry that it had been edited")
        #expect(after.id == post.id, "an edit made a second post rather than rewriting one")
        #expect(alice.feed().count == 1)
    }

    @Test("An edit after the window is refused, and the control is not offered first")
    func afterTheWindow() async throws {
        let (alice, clock) = try await member()
        try await alice.send("as it stands", to: nil)
        let post = try #require(alice.feed().first)
        #expect(alice.timeLeft(toEdit: post.id) != nil)

        clock.advance(by: Editing.editWindow + 1)
        #expect(alice.timeLeft(toEdit: post.id) == nil, "a control was offered past the window")
        await #expect(throws: AppSessionError.tooLateToEdit) {
            try await alice.edit(post.id, to: "second thoughts")
        }
        #expect(alice.feed().first?.body == "as it stands")
    }

    @Test("A withdrawn post says withdrawn, in its own words, and is not called deleted")
    func withdrawing() async throws {
        let (alice, _) = try await member()
        try await alice.send("said too fast", to: nil)
        let post = try #require(alice.feed().first)

        try await alice.withdraw(post.id)

        let after = try #require(alice.feed().first)
        #expect(after.isWithdrawn)
        #expect(after.body == "This post was withdrawn.")
        #expect(!after.body.localizedCaseInsensitiveContains("delet"))
        #expect(alice.feed().count == 1)
    }

    @Test("Withdrawing a photo post takes the picture back with the words")
    func withdrawingAPhotoPost() async throws {
        let mailbox = InMemoryMailbox()
        let (alice, _) = try await member()
        try await alice.post(SendingPhotoTests.photo(caption: "the view"), through: mailbox)
        let post = try #require(alice.feed().first)
        #expect(!post.media.isEmpty)

        try await alice.withdraw(post.id)

        let after = try #require(alice.feed().first)
        #expect(after.isWithdrawn)
        #expect(after.media.isEmpty, "the picture survived the withdrawal")
        #expect(after.body == "This post was withdrawn.")
    }

    @Test("A photo post is not offered an edit, because the fold would refuse one")
    func aPhotoPostCannotBeEdited() async throws {
        let mailbox = InMemoryMailbox()
        let (alice, _) = try await member()
        try await alice.post(SendingPhotoTests.photo(caption: "as taken"), through: mailbox)
        let post = try #require(alice.feed().first)

        #expect(alice.timeLeft(toEdit: post.id) == nil)
        #expect(alice.timeLeft(toWithdraw: post.id) != nil, "a photo post can still be withdrawn")

        try? await alice.edit(post.id, to: "different words")
        #expect(alice.feed().first?.body == "as taken")
    }

    @Test("A comment can be rewritten and withdrawn, and says which it was")
    func comments() async throws {
        let (alice, _) = try await member()
        try await alice.send("the thing itself", to: nil)
        let post = try #require(alice.feed().first)
        try await alice.comment(on: post, text: "frist")

        let comment = try #require(alice.comments(on: post).first)
        #expect(comment.isMine)
        try await alice.edit(comment.id, to: "first")
        #expect(alice.comments(on: post).first?.body == "first")
        #expect(alice.comments(on: post).first?.editedAt != nil)

        try await alice.withdraw(comment.id)
        let after = try #require(alice.comments(on: post).first)
        #expect(after.isWithdrawn)
        #expect(after.body == "This comment was withdrawn.")
    }

    @Test("Somebody else's post is not this member's to change")
    func notYours() async throws {
        let mailbox = InMemoryMailbox()
        let (alice, _) = try await member()
        let bob = TestSession.make()
        await bob.load()
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await bob.sync(through: mailbox)

        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        try await alice.send("mine", to: nil)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        let post = try #require(alice.feed().first)
        #expect(bob.feed().contains { $0.id == post.id }, "precondition: Bob holds Alice's post")
        #expect(bob.timeLeft(toEdit: post.id) == nil)
        await #expect(throws: AppSessionError.notYourMessage) {
            try await bob.edit(post.id, to: "not yours")
        }
        await #expect(throws: AppSessionError.notYourMessage) { try await bob.withdraw(post.id) }
        #expect(alice.feed().first?.body == "mine")
    }
}

@Suite("What is being looked at")
struct ViewedItemTests {
    @Test("A post reduces to the same shape a message does, keeping its own entry")
    func fromAPost() {
        let entry = EntryHash(rawValue: Data([4, 2]))
        let author = Member(id: ParticipantID(rawValue: Data(repeating: 7, count: 32)), displayName: "Robin")
        let at = Date(timeIntervalSince1970: 1_786_635_000)
        let post = OutpostPost(
            id: PostID(entry: entry), author: author, body: "the view", postedAt: at,
            commentCount: 0, isMine: false,
            media: [
                MediaAttachment(
                    reference: AttachmentReference(
                        id: AttachmentID(), key: Data(repeating: 1, count: 32),
                        digest: Data(repeating: 2, count: 32), byteCount: 10),
                    kind: .image, width: 4, height: 3, preview: nil)
            ])

        let item = ViewedItem(post)
        #expect(item.entry == entry)
        #expect(item.author == author)
        #expect(item.words == "the view")
        #expect(item.at == at)
        #expect(!item.isMine)
        #expect(item.isMedia, "a report would have called a photo post words")
    }

    @Test("A message reduces the same way, and words are not called a photo")
    func fromAMessage() {
        let entry = EntryHash(rawValue: Data([9]))
        let message = Message(
            id: MessageID(entry: entry),
            author: Member(id: ParticipantID(rawValue: Data(repeating: 3, count: 32)), displayName: "Sam"),
            body: "said aloud", sentAt: Date(timeIntervalSince1970: 1_786_635_000), isMine: true)

        let item = ViewedItem(message)
        #expect(item.entry == entry)
        #expect(item.isMine)
        #expect(!item.isMedia)
        #expect(item.words == "said aloud")
    }
}
