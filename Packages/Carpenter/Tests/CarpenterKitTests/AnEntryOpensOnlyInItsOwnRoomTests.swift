@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import CryptoKit
import Foundation
import Testing

@MainActor
@Suite("An entry opens only under the key of the room it names", .serialized)
struct AnEntryOpensOnlyInItsOwnRoomTests {
    @MainActor
    private struct Kitchen {
        let t: RoomOfThree
        let room: RoomID

        static func make() async throws -> Kitchen {
            let t = try await RoomOfThree.make()
            let room = try await t.alice.createRoom(named: "Kitchen")
            try await join(t.sam, into: room, of: t.alice, through: t.mailbox)
            try await t.alice.send("only Sam and me", to: room)
            try await t.settle()
            try #require(t.alice.roster(of: room).members == [t.aliceID, t.samID], "precondition: Carol is not in the kitchen")
            try #require(t.carol.chains[room] == nil, "precondition: Carol holds no key to the kitchen")
            return Kitchen(t: t, room: room)
        }

        func carolWrites(_ sealed: SealedPayload) throws -> Entry {
            let carol = try #require(t.carol.enrolment)
            let entry = try Entry.append(
                after: t.carol.head, author: carol.identity.id, device: carol.device,
                clock: t.carol.replica.frontier, wallTime: TestSession.now, room: room, payload: sealed,
                roomLink: RoomLink(previous: nil))
            _ = try t.alice.replica.integrate(entry)
            t.alice.refresh()
            return entry
        }

        var carolsFeed: FeedKey {
            FeedKey(author: t.carolID, device: t.carol.enrolment!.device.id)
        }

        func expectNothingChanged(after entry: Entry) {
            #expect(t.alice.entryOpener()(entry) == nil, "Alice's phone opened an entry for the kitchen that Carol wrote without its key")
            #expect(
                !t.alice.messages(in: room).contains { $0.body == "from Carol" },
                "Carol's words were drawn in a room she has never been in")
            #expect(t.alice.roster(of: room).members == [t.aliceID, t.samID])
            #expect(t.alice.rooms.first { $0.id == room }?.name == "Kitchen", "Carol renamed a room she has never been in")
        }
    }

    @Test("An entry sealed under the key of a room its writer shares with you does not open in another room")
    func anotherRoomsKeyDoesNotOpenIt() async throws {
        let k = try await Kitchen.make()
        let lanterns = try #require(k.t.carol.chains[k.t.room])
        let epoch = try #require(lanterns.highestKnownEpoch)

        for payload in [try Payload.post("from Carol"), try Payload.roomProfile(name: "Carol's kitchen")] {
            let sealed = try payload.sealed(at: epoch, using: lanterns, by: k.carolsFeed)
            k.expectNothingChanged(after: try k.carolWrites(sealed))
        }
    }

    @Test("An entry in a room does not open under the secret its writer shares with you")
    func thePairSecretDoesNotOpenARoom() async throws {
        let k = try await Kitchen.make()
        let pair = try #require(k.t.carol.baseSecret(with: k.t.aliceID))
        let (madeUp, _) = EpochChain.create(room: k.room)

        for payload in [try Payload.post("from Carol"), try Payload.roomProfile(name: "Carol's kitchen")] {
            let sealed = try payload.sealed(at: .initial, using: madeUp, by: k.carolsFeed, alsoFor: pair)
            k.expectNothingChanged(after: try k.carolWrites(sealed))
        }
    }

    @Test("What somebody never let into a room seals there is not drawn, counted unread or announced")
    func aStrangersSealedEntryIsNotDrawn() async throws {
        let k = try await Kitchen.make()
        try #require(k.t.alice.rooms.first { $0.id == k.room }?.hasUnread == false, "precondition: nothing unread")
        let (madeUp, _) = EpochChain.create(room: k.room)

        _ = try k.carolWrites(try Payload.post("from Carol").sealed(at: .initial, using: madeUp, by: k.carolsFeed))

        #expect(
            !k.t.alice.messages(in: k.room).contains { $0.author.id == k.t.carolID },
            "a bubble from Carol was drawn in a room she has never been in")
        #expect(k.t.alice.rooms.first { $0.id == k.room }?.hasUnread == false, "Carol made a room she is not in show unread")
        #expect(k.t.alice.latestIncomingMessage()?.room != k.room, "a notification would have named Carol in a room she is not in")
    }

    @Test("What a member seals under a key this phone does not hold yet is still drawn as unreadable")
    func aMembersSealedEntryIsDrawn() async throws {
        let k = try await Kitchen.make()
        let sam = try #require(k.t.sam.enrolment)
        let (madeUp, _) = EpochChain.create(room: k.room)
        let entry = try Entry.append(
            after: k.t.sam.head, author: sam.identity.id, device: sam.device, clock: k.t.sam.replica.frontier,
            wallTime: TestSession.now, room: k.room,
            payload: try Payload.post("under a newer key").sealed(
                at: .initial, using: madeUp, by: FeedKey(author: sam.identity.id, device: sam.device.id)),
            roomLink: RoomLink(previous: k.t.sam.roomHeads[k.room]?.hash))
        _ = try k.t.alice.replica.integrate(entry)
        k.t.alice.refresh()

        #expect(k.t.alice.messages(in: k.room).contains { $0.id.entry == entry.hash }, "a member's unreadable message vanished")
    }

    @Test("The copy for the owner of an Outpost opens only for a comment or a reaction, the two the app writes")
    func theOwnersCopyIsOnlyForACommentOrAReaction() async throws {
        let k = try await Kitchen.make()
        let pair = try #require(k.t.carol.baseSecret(with: k.t.aliceID))
        let (madeUp, _) = EpochChain.create(room: RoomID.outpost(of: k.t.carolID))
        let carol = try #require(k.t.carol.enrolment)
        let target = try #require(k.t.alice.messages(in: k.room).first?.id.entry)

        func written(_ payload: Payload) throws -> Entry {
            try Entry.append(
                after: k.t.carol.head, author: carol.identity.id, device: carol.device,
                clock: k.t.carol.replica.frontier, wallTime: TestSession.now, room: nil,
                payload: try payload.sealed(at: .initial, using: madeUp, by: k.carolsFeed, alsoFor: pair))
        }

        let comment = try written(try Payload.comment(on: target, text: "nice"))
        #expect(k.t.alice.entryOpener()(comment)?.type == .comment, "precondition: the copy the app writes opens")

        for payload in [try Payload.post("on Carol's wall"), try Payload.roomProfile(name: "Carol's kitchen")] {
            #expect(
                k.t.alice.entryOpener()(try written(payload)) == nil,
                "the owner's copy opened for something the app never seals that way")
        }
    }
}
