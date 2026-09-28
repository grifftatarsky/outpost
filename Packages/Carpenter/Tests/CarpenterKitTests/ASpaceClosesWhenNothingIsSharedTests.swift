@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("The space kept for somebody closes nine days after you last share anything with them", .serialized)
struct ASpaceClosesWhenNothingIsSharedTests {
    @MainActor
    private struct Pair {
        let mailbox: InMemoryMailbox
        let clock: TestClock
        let alice: AppSession
        let bob: AppSession
        let room: RoomID

        var aliceID: ParticipantID { alice.enrolment!.identity.id }
        var bobID: ParticipantID { bob.enrolment!.identity.id }

        func round(_ count: Int = 1) async throws {
            for _ in 0..<count {
                for session in [alice, bob] { try await session.sync(through: mailbox, media: mailbox) }
            }
        }

        func bobReadsAlice() async -> Bool {
            let bobs = LocalPairStore.account(of: bobID)
            return await mailbox.readers(ofSpaceOf: aliceID).contains { $0.contains(bobs) }
        }

        var aliceWritesToBob: Bool { alice.peers().contains { $0.them == bobID } }
    }

    private func pair() async throws -> Pair {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let (alice, bob) = (TestSession.make(clock: clock), TestSession.make(clock: clock))
        for (session, name) in [(alice, "Alice"), (bob, "Bob")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        let room = try await alice.createRoom(named: "Darkroom")
        try await join(bob, into: room, of: alice, through: mailbox, media: mailbox)
        let pair = Pair(mailbox: mailbox, clock: clock, alice: alice, bob: bob, room: room)
        try await pair.round(3)
        try #require(await pair.bobReadsAlice(), "precondition: Bob reads the space Alice keeps for him")
        return pair
    }

    @Test("A removed person's space stays open for the nine days a packet waits, and then closes")
    func theSpaceClosesAfterNineDays() async throws {
        let t = try await pair()
        try await t.alice.remove(t.bobID, from: t.room)
        try await t.round(3)
        #expect(t.aliceWritesToBob, "somebody just removed stopped being written to before their notice could wait")

        t.clock.advance(by: SyncSession.packetWaitsFor - 3_600)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        #expect(await t.bobReadsAlice(), "the space closed before the nine days a packet waits were up")

        t.clock.advance(by: 7_200)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        #expect(!(await t.bobReadsAlice()), "the space outlived nine days of sharing nothing")
        #expect(!t.aliceWritesToBob, "something is still written to somebody whose space is closed")
    }

    @Test("Somebody you still share a room with keeps their space, whatever an old mark says")
    func sharingOutweighsAnyMark() async throws {
        let t = try await pair()
        try #require(t.alice.persisted.pairBook[t.bobID] != nil, "precondition: Alice keeps an entry for Bob")
        t.alice.persisted.pairBook[t.bobID]?.sharedNothingSince = .distantPast

        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        #expect(await t.bobReadsAlice(), "a stale mark closed the space of somebody still in the room")
        #expect(t.alice.persisted.pairBook[t.bobID]?.sharedNothingSince == nil, "the mark outlived the room it contradicts")
    }

    @Test("Somebody who can still see your Outpost keeps their space after your last room with them ends")
    func anOutpostIsSharing() async throws {
        let t = try await pair()
        try await t.alice.allowOutpost(t.bobID, everything: true)
        try await t.round(3)
        try await t.alice.remove(t.bobID, from: t.room)
        try await t.round(3)

        t.clock.advance(by: SyncSession.packetWaitsFor + 3_600)
        try await t.round(2)
        #expect(await t.bobReadsAlice(), "the space closed while Bob could still see Alice's Outpost")
    }

    @Test("Sharing a room again after the space closed opens a new one, and words cross again")
    func sharingAgainOpensANewSpace() async throws {
        let t = try await pair()
        try await t.alice.remove(t.bobID, from: t.room)
        try await t.round(3)
        t.clock.advance(by: SyncSession.packetWaitsFor + 3_600)
        try await t.round(2)
        try #require(!(await t.bobReadsAlice()), "precondition: the space closed")

        let again = try await t.alice.createRoom(named: "Second darkroom")
        try await join(t.bob, into: again, of: t.alice, through: t.mailbox, media: t.mailbox)
        try await t.round(3)
        #expect(await t.bobReadsAlice(), "sharing a room again did not open a new space")

        try await t.alice.send("together again", to: again)
        try await t.round(3)
        #expect(t.bob.messages(in: again).contains { $0.body == "together again" }, "words did not cross the new space")
    }
}
