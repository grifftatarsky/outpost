import Foundation
import Testing

@testable import CarpenterKit

@Suite("Fold")
struct FoldTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func text(_ rendered: RenderedEntry?) -> String? {
        guard case .text(let value) = rendered?.content else { return nil }
        return value
    }

    @Test("A post renders as its text")
    func post() throws {
        var alice = Author()
        let entry = try alice.post("a balloon that made a decision", at: start)

        let rendered = Fold.render([entry], using: alice.chain)

        #expect(rendered.count == 1)
        #expect(text(rendered.first) == "a balloon that made a decision")
        #expect(rendered.first?.isEdited == false)
    }

    @Test("An edit replaces the text and marks the entry as edited")
    func edit() throws {
        var alice = Author()
        let post = try alice.post("teh mooring mast", at: start)
        let edit = try alice.append(
            Payload.edit(post.hash, to: "the mooring mast"), at: start.addingTimeInterval(60))

        let rendered = Fold.render([post, edit], using: alice.chain)

        #expect(rendered.count == 1)
        #expect(text(rendered.first) == "the mooring mast")
        #expect(rendered.first?.editedAt == start.addingTimeInterval(60))
    }

    @Test("The last edit in causal order wins")
    func lastEditWins() throws {
        var alice = Author()
        let post = try alice.post("first", at: start)
        let one = try alice.append(Payload.edit(post.hash, to: "second"), at: start.addingTimeInterval(1))
        let two = try alice.append(Payload.edit(post.hash, to: "third"), at: start.addingTimeInterval(2))

        #expect(text(Fold.render([post, one, two], using: alice.chain).first) == "third")
        #expect(text(Fold.render([two, one, post], using: alice.chain).first) == "third")
    }

    @Test("Nobody can edit someone else's words")
    func editsAreAuthorOnly() throws {
        var alice = Author()
        var mallory = Author(chain: alice.chain)
        let post = try alice.post("what she said", at: start)
        let forgery = try mallory.append(
            Payload.edit(post.hash, to: "what he wishes she said"), at: start.addingTimeInterval(1))

        #expect(text(Fold.render([post, forgery], using: alice.chain).first) == "what she said")
    }

    @Test("A tombstone withdraws the entry but leaves it in place")
    func tombstone() throws {
        var alice = Author()
        let post = try alice.post("regrettable", at: start)
        let removal = try alice.append(Payload.tombstone(post.hash), at: start.addingTimeInterval(1))

        let rendered = Fold.render([post, removal], using: alice.chain)

        #expect(rendered.count == 1)
        #expect(rendered.first?.content == .withdrawn)
    }

    @Test("Nobody can withdraw someone else's entry")
    func tombstonesAreAuthorOnly() throws {
        var alice = Author()
        var mallory = Author(chain: alice.chain)
        let post = try alice.post("inconvenient", at: start)
        let forgery = try mallory.append(
            Payload.tombstone(post.hash), at: start.addingTimeInterval(1))

        #expect(text(Fold.render([post, forgery], using: alice.chain).first) == "inconvenient")
    }

    @Test("An edit arriving after a withdrawal does not bring the entry back")
    func withdrawalIsFinal() throws {
        var alice = Author()
        let post = try alice.post("regrettable", at: start)
        let removal = try alice.append(Payload.tombstone(post.hash), at: start.addingTimeInterval(1))
        let late = try alice.append(
            Payload.edit(post.hash, to: "actually fine"), at: start.addingTimeInterval(2))

        #expect(Fold.render([post, removal, late], using: alice.chain).first?.content == .withdrawn)
    }

    @Test("Anyone may react, and reactions collect by emoji")
    func reactions() throws {
        var alice = Author()
        var bob = Author(chain: alice.chain)
        var carol = Author(chain: alice.chain)
        let post = try alice.post("dirigible means steerable", at: start)

        let one = try bob.append(
            Payload.reaction(post.hash, emoji: "🎈"), at: start.addingTimeInterval(1))
        let two = try carol.append(
            Payload.reaction(post.hash, emoji: "🎈"), at: start.addingTimeInterval(2))

        let rendered = Fold.render([post, one, two], using: alice.chain)

        #expect(rendered.first?.reactions["🎈"] == [bob.identity.id, carol.identity.id])
    }

    @Test("A member's second reaction replaces their first")
    func oneReactionPerMember() throws {
        var alice = Author()
        var bob = Author(chain: alice.chain)
        let post = try alice.post("hydrogen, obviously", at: start)

        let first = try bob.append(
            Payload.reaction(post.hash, emoji: "🎈"), at: start.addingTimeInterval(1))
        let second = try bob.append(
            Payload.reaction(post.hash, emoji: "🔥"), at: start.addingTimeInterval(2))

        let rendered = Fold.render([post, first, second], using: alice.chain)

        #expect(rendered.first?.reactions["🎈"] == nil)
        #expect(rendered.first?.reactions["🔥"] == [bob.identity.id])
    }

    @Test("A reaction with no emoji removes it and leaves no empty bucket")
    func reactionRemoval() throws {
        var alice = Author()
        var bob = Author(chain: alice.chain)
        let post = try alice.post("helium coward", at: start)

        let added = try bob.append(
            Payload.reaction(post.hash, emoji: "🎈"), at: start.addingTimeInterval(1))
        let cleared = try bob.append(
            Payload.reaction(post.hash, emoji: nil), at: start.addingTimeInterval(2))

        #expect(Fold.render([post, added, cleared], using: alice.chain).first?.reactions.isEmpty == true)
    }

    @Test("An operation targeting an entry we do not hold is ignored, not fatal")
    func danglingReferences() throws {
        var alice = Author()
        let missing = EntryHash(rawValue: Data(repeating: 7, count: 32))
        let edit = try alice.append(Payload.edit(missing, to: "nowhere"), at: start)
        let reaction = try alice.append(
            Payload.reaction(missing, emoji: "🎈"), at: start.addingTimeInterval(1))

        #expect(Fold.render([edit, reaction], using: alice.chain).isEmpty)
    }

    @Test("An unknown type renders its fallback string")
    func unknownTypeRendersFallback() throws {
        var alice = Author()
        let poll = Payload(
            type: PayloadType(rawValue: 4_242), version: 1, body: Data([9]),
            fallbackText: "Cassilda posted a poll")
        let entry = try alice.append(poll, at: start)

        let rendered = Fold.render([entry], using: alice.chain)

        #expect(rendered.count == 1)
        #expect(
            rendered.first?.content
                == .unrenderable(type: PayloadType(rawValue: 4_242), fallback: "Cassilda posted a poll"))
    }

    @Test("A known type with a body this version cannot read also falls back")
    func unreadableBodyFallsBack() throws {
        var alice = Author()
        let future = Payload(
            type: .post, version: 99, body: Data([0xFF, 0xFE]), fallbackText: "a newer kind of post")
        let entry = try alice.append(future, at: start)

        #expect(
            Fold.render([entry], using: alice.chain).first?.content
                == .unrenderable(type: .post, fallback: "a newer kind of post"))
    }

    @Test("An unknown entry can still be reacted to")
    func reactionsOnUnknownEntries() throws {
        var alice = Author()
        var bob = Author(chain: alice.chain)
        let poll = Payload(
            type: PayloadType(rawValue: 4_242), version: 1, body: Data([9]), fallbackText: "a poll")
        let entry = try alice.append(poll, at: start)
        let reaction = try bob.append(
            Payload.reaction(entry.hash, emoji: "🎈"), at: start.addingTimeInterval(1))

        #expect(Fold.render([entry, reaction], using: alice.chain).first?.reactions["🎈"] == [bob.identity.id])
    }

    @Test("The rendered order does not depend on the order entries were handed over")
    func orderIsIndependentOfInput() throws {
        var alice = Author()
        let first = try alice.post("one", at: start)
        let second = try alice.post("two", at: start.addingTimeInterval(1))
        let third = try alice.post("three", at: start.addingTimeInterval(2))

        let forwards = Fold.render([first, second, third], using: alice.chain).map(\.id)
        let backwards = Fold.render([third, second, first], using: alice.chain).map(\.id)
        let jumbled = Fold.render([second, third, first], using: alice.chain).map(\.id)

        #expect(forwards == [first.hash, second.hash, third.hash])
        #expect(backwards == forwards)
        #expect(jumbled == forwards)
    }
}

@Suite("Every payload type is classified")
struct PayloadTypeClassificationTests {
    @Test("No declared type is left to fall through into a transcript by accident")
    func everyKnownTypeIsDeliberate() {
        let conversational: Set<PayloadType> = [.post, .edit, .tombstone, .reaction, .media]

        for type in PayloadType.allKnown {
            #expect(
                conversational.contains(type) != PayloadType.plumbing.contains(type),
                "payload type \(type.rawValue) is unclassified or classified twice")
        }
    }

    @Test("An epoch change never reaches a room's transcript")
    func epochChangeIsPlumbing() {
        #expect(PayloadType.plumbing.contains(.epochChange))
    }

    @Test("A type this client has never heard of still renders, per §7")
    func unknownTypesAreNotSilentlyDropped() {
        #expect(!PayloadType.plumbing.contains(PayloadType(rawValue: 9_999)))
    }
}

@Suite("A wall's machinery is addressed to the wall")
struct WallPlumbingRoutingTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func feed(of author: Author, room: RoomID?) throws -> [OutpostPost] {
        var writing = author
        let entry = try writing.append(
            Payload(type: PayloadType(rawValue: 31_337), body: Data([1])), at: start, room: room)
        let rendered = Fold.render([entry], using: writing.chain)
        return Projection(viewer: writing.identity.id, rendered: rendered).feed()
    }

    @Test("A payload this build cannot read, with no room, is drawn as a post")
    func roomlessUnknownBecomesAPost() throws {
        let alice = Author()
        #expect(
            try feed(of: alice, room: nil).count == 1,
            "the premise: an entry with no room is a post, whatever is inside it")
    }

    @Test("The same payload addressed to the wall is drawn nowhere")
    func addressedToTheWallItIsNot() throws {
        let alice = Author()
        let wall = RoomID.outpost(of: alice.identity.id)
        #expect(try feed(of: alice, room: wall).isEmpty, "a wall's machinery reached the feed")
    }

    @Test("A member's wall is the same room wherever it is worked out")
    func theWallIsDerived() {
        let alice = Author()
        let bob = Author()
        #expect(RoomID.outpost(of: alice.identity.id) == RoomID.outpost(of: alice.identity.id))
        #expect(RoomID.outpost(of: alice.identity.id) != RoomID.outpost(of: bob.identity.id))
    }
}
