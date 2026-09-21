@testable import CarpenterApp
@testable import CarpenterKit
@testable import CarpenterUI
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Reacting to a message", .serialized)
struct MessageReactionTests {
    private func joined() async throws -> (
        alice: AppSession, bob: AppSession, room: ConversationID, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, room, mailbox)
    }

    @Test("A reaction lands on the message it names")
    func aReactionLands() async throws {
        let (alice, _, room, _) = try await joined()
        try await alice.send("hello", to: room)
        let message = try #require(alice.messages(in: room).last)

        try await alice.react(to: message.id, in: room, with: "❤️")

        let after = try #require(alice.messages(in: room).last)
        #expect(after.reactions["❤️"]?.count == 1)
        #expect(after.myReaction == "❤️")
    }

    @Test("Reacting to your own message survives the delivery-mark rebuild")
    func reactingToYourOwnMessageSurvivesTheRebuild() async throws {
        let (alice, _, room, _) = try await joined()
        try await alice.send("mine", to: room)
        let message = try #require(alice.messages(in: room).last)
        try #require(message.isMine, "this test only means something on the sender's own path")

        try await alice.react(to: message.id, in: room, with: "🫡")

        let after = try #require(alice.messages(in: room).last)
        #expect(
            after.reactions["🫡"]?.count == 1,
            "the reaction folded and the read model dropped it again")
        #expect(after.myReaction == "🫡")
    }

    @Test("Reacting again replaces what you had")
    func reactingAgainReplaces() async throws {
        let (alice, _, room, _) = try await joined()
        try await alice.send("hello", to: room)
        let message = try #require(alice.messages(in: room).last)

        try await alice.react(to: message.id, in: room, with: "👍")
        try await alice.react(to: message.id, in: room, with: "👎")

        let after = try #require(alice.messages(in: room).last)
        #expect(after.reactions["👍"] == nil, "the old reaction stayed alongside the new one")
        #expect(after.reactions["👎"]?.count == 1)
        #expect(after.myReaction == "👎")
    }

    @Test("Reacting with nothing takes it back")
    func nilTakesItBack() async throws {
        let (alice, _, room, _) = try await joined()
        try await alice.send("hello", to: room)
        let message = try #require(alice.messages(in: room).last)
        try await alice.react(to: message.id, in: room, with: "❤️")

        try await alice.react(to: message.id, in: room, with: nil)

        let after = try #require(alice.messages(in: room).last)
        #expect(after.reactions.isEmpty)
        #expect(after.myReaction == nil)
    }

    @Test("A reaction crosses to everybody else in the room")
    func aReactionCrossesTheRoom() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        try await alice.send("hello", to: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        let theirs = try #require(bob.messages(in: room).last)

        try await bob.react(to: theirs.id, in: room, with: "🔥")
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        let seen = try #require(alice.messages(in: room).last)
        #expect(seen.reactions["🔥"]?.count == 1, "the room never saw the reaction")
        #expect(
            seen.myReaction == nil,
            "somebody else's reaction was reported as the reader's own")
        #expect(try #require(bob.messages(in: room).last).myReaction == "🔥")
    }
}

@Suite("The four emoji somebody actually uses")
struct FavouriteEmojiTests {
    @Test("A device that has learned nothing offers the starting four")
    func startsWithTheDefaults() {
        #expect(FavouriteEmoji.ranked([:]) == ["❤️", "👍", "👎", "🫡"])
    }

    @Test("Use moves an emoji up, and only use does")
    func useRanks() {
        let ranked = FavouriteEmoji.ranked(["🫡": 9, "🔥": 4])
        #expect(ranked.first == "🫡")
        #expect(ranked.contains("🔥"), "something used four times did not make four slots")
        #expect(ranked.count == FavouriteEmoji.slots)
    }

    @Test("Emoji on the same count keep a stable order")
    func tiesAreStable() {
        let counts = ["👍": 3, "👎": 3, "❤️": 3, "🫡": 3, "🔥": 3]
        let first = FavouriteEmoji.ranked(counts)
        for _ in 0..<20 {
            #expect(FavouriteEmoji.ranked(counts) == first, "the bar reshuffled on equal counts")
        }
        #expect(first == ["❤️", "👍", "👎", "🫡"], "the starting order is not the tie-break")
    }

    @Test("Only four are ever offered")
    func fourSlots() {
        let counts = ["🔥": 9, "😮": 8, "👏": 7, "🎈": 6, "💯": 5, "❤️": 1]
        #expect(FavouriteEmoji.ranked(counts) == ["🔥", "😮", "👏", "🎈"])
    }
}
