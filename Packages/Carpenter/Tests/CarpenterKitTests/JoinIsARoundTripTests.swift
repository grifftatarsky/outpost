@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A join is a round trip", .serialized)
struct JoinIsARoundTripTests {
    private func pair() async throws -> (
        alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        return (alice, bob, mailbox)
    }

    private func settle(
        _ everyone: [AppSession], _ mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox) }
        }
    }

    @Test("Somebody removed and asked back is outside until they confirm again")
    func aReJoinIsARoundTripToo() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")
        let bobID = try #require(bob.enrolment?.identity.id)

        let first = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try first.encoded())
        try await settle([alice, bob], mailbox)
        #expect(alice.roster(of: room).members.contains(bobID), "precondition: Bob joined")

        try await alice.remove(bobID, from: room)
        try await settle([alice, bob], mailbox)
        #expect(!alice.roster(of: room).members.contains(bobID))
        #expect(bob.roster(of: room).removal(of: bobID) != nil, "his own copy did not say so")

        let again = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        #expect(
            !alice.roster(of: room).members.contains(bobID),
            "making an invitation put a removed member back before it had been handed over")
        try await settle([alice, bob], mailbox)
        #expect(
            !alice.roster(of: room).members.contains(bobID),
            "a re-invitation admitted somebody who had not answered it")

        try await bob.redeem(inviteCode: try again.encoded())
        try await settle([alice, bob], mailbox, rounds: 8)

        for session in [alice, bob] {
            #expect(
                session.roster(of: room).members.contains(bobID),
                "a confirmed re-invitation did not bring him back")
            #expect(session.roster(of: room).removal(of: bobID) == nil)
        }
    }

    @Test("Refusing the phrase leaves the room with one member, on both devices")
    func refusingAdmitsNobody() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")
        let bobID = try #require(bob.enrolment?.identity.id)

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        #expect(bob.inspect(inviteCode: try invite.encoded()) != nil, "the sheet had nothing to show")

        try await settle([alice, bob], mailbox)

        #expect(alice.roster(of: room).members.count == 1, "a refused invitation admitted somebody")
        #expect(!alice.roster(of: room).members.contains(bobID))
        #expect(alice.roster(of: room).invited.contains(bobID), "the inviter cannot see it pending")
        #expect(bob.rooms.isEmpty, "the joiner was shown a room they refused")
    }

    @Test("Confirming the phrase puts them in, with the room and its history")
    func confirmingAdmits() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("before you arrived", to: room)
        let bobID = try #require(bob.enrolment?.identity.id)

        try await join(bob, into: room, of: alice, through: mailbox)

        #expect(alice.roster(of: room).members.contains(bobID))
        #expect(alice.roster(of: room).invited.isEmpty, "somebody who is in is still listed invited")
        #expect(bob.roster(of: room).members.contains(bobID), "the joiner's own copy left them out")
        #expect(bob.messages(in: room).map(\.body).contains("before you arrived"))
    }

    @Test("A joiner who has confirmed and is waiting can still be let in")
    func waitingIsReachable() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7", access: .founder)
        let bobID = try #require(bob.enrolment?.identity.id)

        try await join(bob, into: room, of: alice, through: mailbox)

        #expect(!alice.roster(of: room).members.contains(bobID), "the founder's room let him past")
        #expect(alice.roster(of: room).confirmed.contains(bobID))
        #expect(bob.rooms.isEmpty, "waiting to be let in is not being in")

        let attestation = try #require(alice.pendingJoins(in: room).first)
        try await alice.decide(on: attestation, admit: true)
        try await settle([alice, bob], mailbox)

        #expect(alice.roster(of: room).members.contains(bobID))
        #expect(bob.rooms.contains { $0.id == room }, "the joiner was let in and never heard")
    }

    @Test("Confirming twice is confirming once")
    func confirmingTwiceTurnsTheKeyOnce() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")
        let before = alice.epochsHeld(in: room)

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await bob.accept(
            invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle([alice, bob], mailbox)

        #expect(alice.roster(of: room).members.count == 2)
        #expect(alice.epochsHeld(in: room) == before + 1, "one join turned the key more than once")
    }

    @Test("Only the inviter relays a confirmation")
    func onlyTheInviterRelays() async throws {
        let (alice, bob, mailbox) = try await pair()
        let carol = TestSession.make()
        await carol.load()
        try await carol.createIdentity(displayName: "Carol")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: room, of: alice, through: mailbox)

        let before = alice.epochsHeld(in: room)
        try await join(carol, into: room, of: bob, through: mailbox)
        try await settle([alice, bob, carol], mailbox)

        let carolID = try #require(carol.enrolment?.identity.id)
        #expect(alice.roster(of: room).members.contains(carolID))
        #expect(
            alice.epochsHeld(in: room) == before + 1,
            "somebody who was not the inviter relayed a confirmation")
    }
}
