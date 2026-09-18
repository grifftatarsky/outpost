import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("A line under your own name", .serialized)
struct BlurbTests {
    private func acquainted() async throws -> (
        alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(
            invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await alice.allowOutpost(try #require(bob.enrolment?.identity.id), everything: true)
        try await settle([alice, bob], through: mailbox)
        return (alice, bob, mailbox)
    }

    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    @Test("A blurb reaches somebody let in")
    func itCrosses() async throws {
        let (alice, bob, mailbox) = try await acquainted()
        try await alice.setBlurb("Keeping the masthead honest")
        try await settle([alice, bob], through: mailbox)

        let aliceID = try #require(alice.enrolment?.identity.id)
        #expect(alice.ownBlurb == "Keeping the masthead honest")
        #expect(bob.blurb(of: aliceID) == "Keeping the masthead honest")
    }

    @Test("Writing a blurb does not hand over your name")
    func theNameIsNotAlongForTheRide() async throws {
        let (alice, bob, mailbox) = try await acquainted()
        await bob.setShowsOthersNames(true)
        #expect(!alice.sharesName, "the default changed and this test is now testing nothing")

        try await alice.setBlurb("Keeping the masthead honest")
        try await settle([alice, bob], through: mailbox)

        let aliceID = try #require(alice.enrolment?.identity.id)
        #expect(bob.blurb(of: aliceID) == "Keeping the masthead honest")
        #expect(
            bob.member(aliceID).isPlaceholder,
            "a blurb announced a name its author never agreed to share")
        #expect(bob.member(aliceID).displayName != "Alice")
    }

    @Test("A blurb does not blank the name you are already drawn by")
    func itDoesNotEraseAName() async throws {
        let (alice, bob, mailbox) = try await acquainted()
        await alice.setSharesName(true)
        await bob.setShowsOthersNames(true)
        try await settle([alice, bob], through: mailbox)

        let aliceID = try #require(alice.enrolment?.identity.id)
        #expect(bob.member(aliceID).displayName == "Alice")

        await alice.setSharesName(false)
        try await alice.setBlurb("Keeping the masthead honest")
        try await settle([alice, bob], through: mailbox)

        #expect(bob.member(aliceID).displayName == "Alice")
        #expect(!bob.member(aliceID).isPlaceholder)
        #expect(bob.blurb(of: aliceID) == "Keeping the masthead honest")
    }

    @Test("Taking a blurb down takes it down for its readers")
    func itCanBeCleared() async throws {
        let (alice, bob, mailbox) = try await acquainted()
        try await alice.setBlurb("Keeping the masthead honest")
        try await settle([alice, bob], through: mailbox)
        try await alice.setBlurb("   ")
        try await settle([alice, bob], through: mailbox)

        let aliceID = try #require(alice.enrolment?.identity.id)
        #expect(alice.ownBlurb == nil)
        #expect(bob.blurb(of: aliceID) == nil)
    }

    @Test("A profile body opens whichever half it carries")
    func bothShapesDecode() throws {
        let nameOnly = try JSONDecoder().decode(
            MemberProfileBody.self, from: Data(#"{"displayName":"Alice"}"#.utf8))
        #expect(nameOnly.name == "Alice")
        #expect(nameOnly.blurb == nil)

        let blurbOnly = try JSONDecoder().decode(
            MemberProfileBody.self, from: Data(#"{"blurb":"On the roof"}"#.utf8))
        #expect(blurbOnly.name == nil)
        #expect(blurbOnly.blurb == "On the roof")

        let blankName = try JSONDecoder().decode(
            MemberProfileBody.self, from: Data(#"{"displayName":"","blurb":"On the roof"}"#.utf8))
        #expect(blankName.name == nil, "an empty name folded as a name")
    }

    @Test("A blurb is cut at the limit rather than refused")
    func itIsCut() async throws {
        let (alice, bob, mailbox) = try await acquainted()
        let long = String(repeating: "a", count: MemberProfileBody.blurbLimit + 40)
        try await alice.setBlurb(long)
        try await settle([alice, bob], through: mailbox)

        let aliceID = try #require(alice.enrolment?.identity.id)
        #expect(bob.blurb(of: aliceID)?.count == MemberProfileBody.blurbLimit)
    }
}
