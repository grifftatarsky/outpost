import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@MainActor
@Suite("What the envelope tells a reader", .serialized)
struct EnvelopeLeakTests {
    private func settle(_ sessions: [AppSession], _ mailbox: InMemoryMailbox, rounds: Int = 8) async throws {
        for _ in 0..<rounds {
            for session in sessions { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    @Test("An entry's clock names nobody outside the conversation it was written in")
    func theClockIsScopedToTheRoom() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for session in [alice, bob, carol] { await session.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")

        let withBob = try await alice.createRoom(named: "Hangar 7")
        let withCarol = try await alice.createRoom(named: "Somewhere else")
        let toBob = try await alice.invite(joinerCode: bob.identityCode(), joining: withBob, mailbox: nil)
        try await bob.redeem(inviteCode: try toBob.encoded())
        let toCarol = try await alice.invite(
            joinerCode: carol.identityCode(), joining: withCarol, mailbox: nil)
        try await carol.redeem(inviteCode: try toCarol.encoded())
        try await settle([alice, bob, carol], mailbox)

        try await carol.send("only carol says this", to: withCarol)
        try await settle([alice, bob, carol], mailbox)
        try await alice.send("for bob", to: withBob)
        try await settle([alice, bob, carol], mailbox)

        let carolID = try #require(carol.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)

        let named = Set(
            bob.replica.allEntries.flatMap { entry in entry.clock.keys.map(\.author) })
        #expect(
            !named.contains(carolID),
            "an entry Bob holds names Carol, who shares no conversation with him")

        let seenByCarol = Set(
            carol.replica.allEntries.flatMap { entry in entry.clock.keys.map(\.author) })
        #expect(
            !seenByCarol.contains(bobID),
            "an entry Carol holds names Bob, who shares no conversation with her")
    }

    @Test("A clock never claims a position from another conversation")
    func theClockCountsOnlyThisRoom() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for session in [alice, bob, carol] { await session.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")

        let withBob = try await alice.createRoom(named: "Hangar 7")
        let withCarol = try await alice.createRoom(named: "Somewhere else")
        let toBob = try await alice.invite(joinerCode: bob.identityCode(), joining: withBob, mailbox: nil)
        try await bob.redeem(inviteCode: try toBob.encoded())
        let toCarol = try await alice.invite(
            joinerCode: carol.identityCode(), joining: withCarol, mailbox: nil)
        try await carol.redeem(inviteCode: try toCarol.encoded())
        try await settle([alice, bob, carol], mailbox)

        for index in 1...5 { try await alice.send("elsewhere \(index)", to: withCarol) }
        try await carol.send("and carol too", to: withCarol)
        try await settle([alice, bob, carol], mailbox)
        try await alice.send("here", to: withBob)
        try await settle([alice, bob, carol], mailbox)

        let here = Set(
            alice.replica.allEntries.filter { $0.room == withBob }
                .map { Position(feed: $0.feedKey, seq: $0.seq) })
        let feedsHere = Set(here.map(\.feed))

        var checked = 0
        for entry in alice.replica.allEntries
        where entry.room == withBob && entry.author == alice.enrolment?.identity.id {
            for feed in entry.clock.keys {
                checked += 1
                #expect(
                    feedsHere.contains(feed),
                    "an entry named a log that has written nothing in this room")
                #expect(
                    here.contains(Position(feed: feed, seq: entry.clock[feed])),
                    "an entry claimed position \(entry.clock[feed]) that this room never held")
            }
        }
        #expect(checked > 0, "this test asserted nothing")
    }

    private struct Position: Hashable {
        let feed: FeedKey
        let seq: UInt64
    }
}
