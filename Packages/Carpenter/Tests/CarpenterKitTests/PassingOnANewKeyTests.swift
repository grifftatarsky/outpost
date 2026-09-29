@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A phone passes a room's new key on only once it holds everything the key's maker had seen", .serialized)
struct PassingOnANewKeyTests {
    @MainActor
    private struct Three {
        let mailbox: InMemoryMailbox
        let alice: AppSession
        let carol: AppSession
        let sam: AppSession
        let room: RoomID

        var aliceID: ParticipantID { alice.enrolment!.identity.id }
        var carolID: ParticipantID { carol.enrolment!.identity.id }
        var samID: ParticipantID { sam.enrolment!.identity.id }

        func settle(rounds: Int = 5) async throws {
            for _ in 0..<rounds {
                for session in [alice, carol, sam] { try await session.sync(through: mailbox, media: mailbox) }
            }
        }

        func key(of session: AppSession) -> EpochNumber? {
            session.chains[room]?.highestKnownEpoch
        }

        func handOverAlicesNewestKeyToCarol() async throws {
            let owed = try alice.grantsOwed().filter { $0.to.them == carolID && $0.grant.room == room }
            let grant = try #require(owed.first?.grant)
            let secret = try #require(carol.pairwiseSecret(with: aliceID))
            try await carol.adopt(grant, from: Peer(secret: secret, them: aliceID, me: carolID), storedAt: .distantFuture)
        }

        func carolTakes(from session: AppSession, writtenBy author: ParticipantID) {
            let held = carol.entriesByHash
            for entry in session.replica.allEntries.sorted(by: { $0.seq < $1.seq })
            where entry.author == author && held[entry.hash] == nil {
                _ = try? carol.replica.integrate(entry)
            }
        }

        func owedByCarol(at epoch: EpochNumber) throws -> [ParticipantID] {
            try carol.grantsOwed().filter { $0.grant.room == room && $0.grant.epoch == epoch }.map { $0.to.them }
        }
    }

    private func three() async throws -> Three {
        let mailbox = InMemoryMailbox()
        let (alice, carol, sam) = (TestSession.make(), TestSession.make(), TestSession.make())
        for (session, name) in [(alice, "Alice"), (carol, "Carol"), (sam, "Sam")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        let room = try await alice.createRoom(named: "Lanterns")
        try await join(carol, into: room, of: alice, through: mailbox)
        try await join(sam, into: room, of: alice, through: mailbox)
        let three = Three(mailbox: mailbox, alice: alice, carol: carol, sam: sam, room: room)
        try await three.settle()
        try #require(alice.roster(of: room).members.count == 3, "precondition: three members")
        try #require(!carol.deviceRecipients(of: three.samID).isEmpty, "precondition: Carol can seal a key to Sam's phone")
        return three
    }

    @Test("A phone that takes a room's new key before it hears of the removal does not hand it to the one removed")
    func theKeyWaitsForTheRemoval() async throws {
        let t = try await three()
        let before = try #require(t.key(of: t.alice))
        try await t.alice.remove(t.samID, from: t.room)
        try await t.handOverAlicesNewestKeyToCarol()
        try #require(t.key(of: t.carol) == before.next, "precondition: Carol holds the new key")
        try #require(t.carol.roster(of: t.room).members.contains(t.samID), "precondition: Carol has not heard of the removal")

        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        try await t.sam.sync(through: t.mailbox, media: t.mailbox)
        #expect(
            t.key(of: t.sam) == before,
            """
            Carol's phone took the room's new key before the removal reached it, still showed Sam as in, \
            and passed the key to him. He would read everything the room says after removing him.
            """)

        try await t.settle()
        try await t.alice.send("said after Sam was removed", to: t.room)
        try await t.settle()
        #expect(t.key(of: t.sam) == before, "the new key reached Sam once everybody had caught up")
        #expect(
            t.carol.messages(in: t.room).contains { $0.body == "said after Sam was removed" },
            "Carol could not read the room under its new key")
        #expect(!t.sam.messages(in: t.room).contains { $0.body == "said after Sam was removed" })
    }

    @Test("A key made after somebody left is passed on only by a phone that has seen them leave")
    func theKeyWaitsForTheDeparture() async throws {
        let t = try await three()
        let before = try #require(t.key(of: t.alice))
        try await t.sam.leave(t.room)
        try await t.sam.sync(through: t.mailbox, media: t.mailbox)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        let made = try #require(t.key(of: t.alice))
        try #require(made == before.next, "precondition: Alice turned the room's key when Sam left")
        try await t.handOverAlicesNewestKeyToCarol()

        t.carolTakes(from: t.alice, writtenBy: t.aliceID)
        try #require(t.carol.roster(of: t.room).members.contains(t.samID), "precondition: Carol has not seen Sam leave")
        try #require(
            t.carol.projection.keyChanges(in: t.room, opening: t.carol.payloadOpener()).contains { $0.link.epoch == made },
            "precondition: Carol holds Alice's record of the change")
        #expect(
            try t.owedByCarol(at: made).isEmpty,
            """
            Carol's phone held the new key and Alice's record of turning it, but not Sam's leaving, which \
            Alice had seen. It passed the key on, and to Sam, whom it still showed as in the room.
            """)

        t.carolTakes(from: t.alice, writtenBy: t.samID)
        try #require(!t.carol.roster(of: t.room).members.contains(t.samID), "precondition: Carol has seen Sam leave")
        let owed = try t.owedByCarol(at: made)
        #expect(owed.contains(t.aliceID), "the key was still held back once everything its maker had seen had arrived")
        #expect(!owed.contains(t.samID))
    }
}

@Suite("What a key's maker writes down about the room")
struct AKeyChangeRecordTests {
    @Test("Nobody without the new key can write down what its maker saw, or take anything out of it")
    func theRecordNeedsTheKey() throws {
        let room = RoomID()
        let (key, link) = try EpochChain.advance(from: EpochSecret.random(), at: .initial, room: room)
        let seen = [EntryHash(rawValue: Data(repeating: 1, count: 32)), EntryHash(rawValue: Data(repeating: 2, count: 32))]
        let made = EpochChangeBody(link: link, heads: seen, under: key)
        #expect(made.isAuthentic(under: key))

        let trimmed = EpochChangeBody(link: link, heads: [seen[0]], proof: made.proof)
        #expect(!trimmed.isAuthentic(under: key), "a record with an entry taken out of it still passed")
        let madeUp = EpochChangeBody(link: link, heads: [], under: EpochSecret.random())
        #expect(!madeUp.isAuthentic(under: key), "a record written without the key passed")
        let moved = EpochChangeBody(
            link: EpochLink(room: RoomID(), epoch: link.epoch, wrapped: link.wrapped), heads: seen, proof: made.proof)
        #expect(!moved.isAuthentic(under: key), "a record carried into another room still passed")
    }
}
