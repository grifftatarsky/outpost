@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Starting a solo", .serialized)
struct SoloTests {
    private func pair() async throws -> (alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        return (alice, bob, mailbox)
    }

    private func settle(_ a: AppSession, _ b: AppSession, _ mailbox: InMemoryMailbox) async throws {
        for _ in 0..<4 {
            try await a.sync(through: mailbox)
            try await b.sync(through: mailbox)
        }
    }

    private func solo(
        between alice: AppSession, and bob: AppSession, through mailbox: InMemoryMailbox
    ) async throws -> RoomID {
        let bobID = try #require(bob.enrolment?.identity.id)
        let room = try await alice.startSolo(with: bobID)
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle(alice, bob, mailbox)
        return room
    }

    @Test("A solo lists as one on both sides, from the moment it is made")
    func listsAsASoloOnBothSides() async throws {
        let (alice, bob, mailbox) = try await pair()
        let bobID = try #require(bob.enrolment?.identity.id)

        let room = try await alice.startSolo(with: bobID)
        #expect(alice.rooms.first { $0.id == room }?.isDirect == true, "the founder's side, before anybody is asked")

        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        #expect(alice.rooms.first { $0.id == room }?.isDirect == true, "still a solo once somebody is asked")

        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle(alice, bob, mailbox)
        #expect(bob.rooms.first { $0.id == room }?.isDirect == true, "the invitee's side")

        let ordinary = try await alice.createRoom(named: "Lanterns")
        #expect(alice.rooms.first { $0.id == ordinary }?.isDirect == false)
    }

    @Test("Each side titles a solo by the other person, as that device knows them")
    func titledByTheOtherPerson() async throws {
        let (alice, bob, mailbox) = try await pair()
        let aliceID = try #require(alice.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)

        let room = try await solo(between: alice, and: bob, through: mailbox)

        #expect(alice.rooms.first { $0.id == room }?.name == Member.placeholder(bobID).displayName)
        #expect(bob.rooms.first { $0.id == room }?.name == Member.placeholder(aliceID).displayName)
        #expect(bob.rooms.first { $0.id == room }?.name != "Bob", "a solo must never be titled by the viewer's own name")

        await alice.optIntoNames()
        await bob.optIntoNames()
        try await settle(alice, bob, mailbox)
        #expect(alice.rooms.first { $0.id == room }?.name == "Bob")
        #expect(bob.rooms.first { $0.id == room }?.name == "Alice")
    }

    @Test("A solo's introduction names the person it is with")
    func greetingNamesThePerson() async throws {
        let (alice, bob, mailbox) = try await pair()
        let aliceID = try #require(alice.enrolment?.identity.id)
        let room = try await solo(between: alice, and: bob, through: mailbox)

        let greeting = try #require(bob.greeting(for: room))
        #expect(greeting.name == Member.placeholder(aliceID).displayName)
        #expect(greeting.invitedBy?.id == aliceID)
    }

    @Test("A solo's first notice says who started it, and names no room")
    func firstNoticeNamesNobodyElse() async throws {
        let (alice, bob, mailbox) = try await pair()
        let aliceID = try #require(alice.enrolment?.identity.id)
        let room = try await solo(between: alice, and: bob, through: mailbox)

        let first = bob.transcript(in: room).compactMap { item -> RoomNotice.Kind? in
            if case .notice(let notice) = item { return notice.kind }
            return nil
        }.first
        guard case .startedSolo(let by) = first else {
            Issue.record("the first notice was not the solo being started: \(String(describing: first))")
            return
        }
        #expect(by.id == aliceID)
    }

    @Test("A profile written before kinds existed reads as a room")
    func oldProfilesAreRooms() throws {
        let body = try JSONDecoder().decode(RoomProfileBody.self, from: Data(#"{"name":"Lanterns"}"#.utf8))
        #expect(body.kind == nil)
        let payload = try Payload.roomProfile(name: "Lanterns")
        #expect(try payload.decode(RoomProfileBody.self).kind == .room)
    }

    @Test("The picker names people only where names are shown")
    func pickerHonoursTheReceiveSwitch() async throws {
        let (alice, bob, mailbox) = try await pair()
        let aliceID = try #require(alice.enrolment?.identity.id)
        _ = try await solo(between: alice, and: bob, through: mailbox)
        await alice.setSharesName(true)
        try await settle(alice, bob, mailbox)

        #expect(bob.connections().first { $0.id == aliceID }?.person.isPlaceholder == true, "shown by name with the switch off")
        await bob.setShowsOthersNames(true)
        #expect(bob.connections().first { $0.id == aliceID }?.person.displayName == "Alice")
    }
}
