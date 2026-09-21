@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Being introduced to a room", .serialized)
struct JoinPromptTests {
    private func joined() async throws -> (alice: AppSession, bob: AppSession, room: ConversationID) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, room)
    }

    @Test("Somebody brought into a room is told what it is, and who brought them")
    func theyAreToldWhatItIs() async throws {
        let (alice, bob, room) = try await joined()

        let greeting = try #require(bob.greeting(for: room), "Bob was dropped straight into a room")
        #expect(greeting.name == "Hangar 7")
        #expect(greeting.invitedBy?.id == alice.enrolment?.identity.id)
        #expect(greeting.invitedBy?.displayName == "Alice")
        #expect(
            Set(greeting.members.map(\.id))
                == Set([alice.enrolment?.identity.id, bob.enrolment?.identity.id].compactMap { $0 }),
            "the room did not say who is in it")
        #expect(greeting.access == .open)
    }

    @Test("The person who made the room is not introduced to it")
    func theFounderIsNotGreeted() async throws {
        let (alice, _, room) = try await joined()
        #expect(alice.greeting(for: room) == nil)
    }

    @Test("It is shown once and then the room opens to its conversation")
    func shownOnce() async throws {
        let (_, bob, room) = try await joined()
        #expect(bob.greeting(for: room) != nil)

        await bob.acknowledgeGreeting(for: room)

        #expect(bob.greeting(for: room) == nil, "the introduction came back after being read")
    }

    @Test("A room that asks for approval says so, in full")
    func thePolicyIsShownInFull() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7", access: .anyMember)
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.decide(on: invite.attestation, admit: true)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        let greeting = try #require(bob.greeting(for: room))
        #expect(greeting.access == .anyMember, "the room described itself as something else")
    }

    @Test("A member with no name is shown as a code rather than given one")
    func unnamedMembersAreNotInvented() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        let greeting = try #require(bob.greeting(for: room))
        for member in greeting.members {
            #expect(
                !member.displayName.isEmpty,
                "somebody was drawn with no label at all, which is worse than a code")
        }
    }
}
