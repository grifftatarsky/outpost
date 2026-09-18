@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Waiting to be let in", .serialized)
struct WaitingToBeLetInTests {
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

    @Test("A confirmed joiner has something to draw while they wait")
    func waitingHasARow() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7", access: .founder)

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await settle([alice, bob], mailbox)

        #expect(bob.rooms.isEmpty, "a room the device does not hold was listed as a room")
        let waiting = try #require(bob.awaitingAdmission.first)
        #expect(waiting.room == room)
        #expect(waiting.invitedBy.id == alice.enrolment?.identity.id)
        // Both sides derive it from the joiner's nonce, so the joiner has it as soon as they
        // redeem and the inviter has it once the confirmation reaches them.
        #expect(waiting.phrase == bob.phrase(for: invite.attestation))
        #expect(waiting.phrase?.count == invite.attestation.phraseLength.rawValue)
        #expect(bob.awaitingAdmission.count == 1)
    }

    @Test("The row goes when the room arrives")
    func waitingClears() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")

        try await join(bob, into: room, of: alice, through: mailbox)

        #expect(bob.rooms.contains { $0.id == room })
        #expect(bob.awaitingAdmission.isEmpty, "somebody in a room was still listed as waiting")
    }

    @Test("Refusing the phrase leaves nothing waiting")
    func refusingWaitsForNothing() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        #expect(bob.inspect(inviteCode: try invite.encoded()) != nil)
        try await settle([alice, bob], mailbox)

        #expect(bob.awaitingAdmission.isEmpty)
        #expect(bob.rooms.isEmpty)
    }

    @Test("The joiner can still find the phrase after they are in")
    func thePhraseSurvivesTheJoin() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")

        try await join(bob, into: room, of: alice, through: mailbox)

        let invitation = try #require(
            bob.ownInvitation(to: room), "the joiner lost the invitation they arrived on")
        #expect(bob.phrase(for: invitation.attestation)?.isEmpty == false)
        #expect(invitation.attestation.inviter == alice.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)
        let theirs = try #require(alice.roster(of: room).requests[bobID])
        #expect(
            alice.phrase(for: theirs) == bob.phrase(for: invitation.attestation),
            "the two sides derive different phrases for the same join")
    }

    @Test("The phrase survives a relaunch")
    func thePhraseSurvivesARelaunch() async throws {
        let mailbox = InMemoryMailbox()
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "waiting-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let alice = TestSession.make()
        let bob = TestSession.make(keychain: keychain, at: directory)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: room, of: alice, through: mailbox)
        let phrase = try #require(bob.ownInvitation(to: room)?.attestation.testPhrase)

        let relaunched = TestSession.make(keychain: keychain, at: directory)
        await relaunched.load()

        #expect(relaunched.ownInvitation(to: room)?.attestation.testPhrase == phrase)
    }
}

@MainActor
@Suite("The phrase outlives everything", .serialized)
struct PhraseSurvivesEverythingTests {
    @Test("The phrase survives the invitation lapsing")
    func survivesTheLapse() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: room, of: alice, through: mailbox)
        let phrase = try #require(bob.ownInvitation(to: room)?.attestation.testPhrase)

        clock.advance(by: 7 * 24 * 60 * 60)
        for _ in 0..<6 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(
            bob.ownInvitation(to: room)?.attestation.testPhrase == phrase,
            "the joiner lost the phrase when the invitation they arrived on lapsed")
        #expect(bob.roster(of: room).members.contains(try #require(bob.enrolment?.identity.id)))
        #expect(bob.awaitingAdmission.isEmpty, "somebody in the room was still listed as waiting")
    }

    @Test("The room keeps the invitation somebody arrived on")
    func theRoomKeepsIt() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: room, of: alice, through: mailbox)
        let bobID = try #require(bob.enrolment?.identity.id)
        let phrase = try #require(alice.roster(of: room).requests[bobID]?.testPhrase)

        clock.advance(by: 30 * 24 * 60 * 60)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(alice.roster(of: room).requests[bobID]?.testPhrase == phrase)
        #expect(
            alice.roster(of: room).confirmedAt(bobID) != nil,
            "the room forgot when it recorded the confirmation")
        #expect(bob.ownInvitation(to: room)?.attestation.testPhrase == phrase)
    }
}
