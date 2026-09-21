@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Comparing codes is offered once, to the people you never compared with", .serialized)
struct ComparingAgainTests {
    private func member(_ name: String, clock: TestClock) async throws -> AppSession {
        let session = TestSession.make(clock: clock)
        await session.load()
        try await session.createIdentity(displayName: name)
        return session
    }

    private func settle(_ everyone: [AppSession], through mailbox: InMemoryMailbox) async throws {
        for _ in 0..<6 {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func admit(
        _ joiner: AppSession, to room: ConversationID, by inviter: AppSession,
        alongside everyone: [AppSession], through mailbox: InMemoryMailbox
    ) async throws {
        let invite = try await inviter.invite(
            joinerCode: joiner.identityCode(), joining: room, mailbox: nil)
        try await joiner.redeem(inviteCode: try invite.encoded())
        try await settle(everyone + [joiner], through: mailbox)
    }

    @Test("Only somebody you neither invited nor were invited by is offered, and only once")
    func offeredOnceToTheRightPeople() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let alice = try await member("Alice", clock: clock)
        let bob = try await member("Bob", clock: clock)
        let carol = try await member("Carol", clock: clock)

        let room = try await alice.createRoom(named: "Hangar 7")
        try await admit(bob, to: room, by: alice, alongside: [alice], through: mailbox)
        try await admit(carol, to: room, by: bob, alongside: [alice, bob], through: mailbox)
        let carolID = try #require(carol.enrolment?.identity.id)
        try #require(alice.roster(of: room).members.contains(carolID), "precondition: Carol is in")

        #expect(alice.comparisonToOffer(in: room) == [carolID], "Alice never compared with Carol")
        #expect(bob.comparisonToOffer(in: room).isEmpty, "Bob compared with Carol when he invited her")
        #expect(
            carol.comparisonToOffer(in: room) == [try #require(alice.enrolment?.identity.id)],
            "Carol never compared with Alice either")

        await alice.markComparisonOffered([carolID])
        #expect(alice.comparisonToOffer(in: room).isEmpty, "offered a second time")
    }

    @Test("Nobody is offered a comparison in a room they were removed from, least of all with their inviter")
    func notAfterARemoval() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let alice = try await member("Alice", clock: clock)
        let bob = try await member("Bob", clock: clock)
        let carol = try await member("Carol", clock: clock)
        let room = try await alice.createRoom(named: "Hangar 7")
        try await admit(bob, to: room, by: alice, alongside: [alice], through: mailbox)
        try await admit(carol, to: room, by: alice, alongside: [alice, bob], through: mailbox)
        try #require(
            bob.comparisonToOffer(in: room) == [try #require(carol.enrolment?.identity.id)],
            "precondition: Bob is offered Carol, and not his inviter")

        try await alice.remove(try #require(bob.enrolment?.identity.id), from: room)
        try await settle([alice, bob, carol], through: mailbox)
        try #require(bob.standing(in: room) != .present)

        #expect(
            bob.comparisonToOffer(in: room).isEmpty,
            "removing Bob forgot who invited him, and the room offered him a comparison with Alice")
    }

    @Test("Alice and Carol, who never met through an invitation, see the same code")
    func theSameCodeOnBothPhones() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let alice = try await member("Alice", clock: clock)
        let bob = try await member("Bob", clock: clock)
        let carol = try await member("Carol", clock: clock)
        let room = try await alice.createRoom(named: "Hangar 7")
        try await admit(bob, to: room, by: alice, alongside: [alice], through: mailbox)
        try await admit(carol, to: room, by: bob, alongside: [alice, bob], through: mailbox)
        let aliceID = try #require(alice.enrolment?.identity.id)
        let carolID = try #require(carol.enrolment?.identity.id)

        let onAlices = try #require(alice.comparisonCode(with: carolID))
        let onCarols = try #require(carol.comparisonCode(with: aliceID))
        #expect(onAlices.map(\.1) == onCarols.map(\.1))
        #expect(onAlices.map(\.0.id) == onCarols.map(\.0.id))
    }

    @Test("Marking the characters as matching is a dated note, and what happened since is counted from it")
    func aNoteToYourself() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let alice = try await member("Alice", clock: clock)
        let bob = try await member("Bob", clock: clock)
        let carol = try await member("Carol", clock: clock)
        let room = try await alice.createRoom(named: "Hangar 7")
        try await admit(bob, to: room, by: alice, alongside: [alice], through: mailbox)
        try await admit(carol, to: room, by: bob, alongside: [alice, bob], through: mailbox)
        let carolID = try #require(carol.enrolment?.identity.id)

        clock.advance(by: 3_600)
        await alice.markChecked(carolID)
        #expect(alice.checkedAt(carolID) == clock.now)
        #expect(alice.comparisonToOffer(in: room).isEmpty, "offered to compare with somebody already checked")
        #expect(alice.devicesAdded(by: carolID, after: clock.now).isEmpty, "nothing has happened since")
        #expect(
            bob.checkedAt(carolID) == nil,
            "a note to yourself reached somebody else")
    }
}
