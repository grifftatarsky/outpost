@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Inviting somebody this phone already knows", .serialized, .tags(.membership))
struct InvitingSomebodyYouAlreadyKnowTests {
    @MainActor private struct World {
        let alice: AppSession
        let bob: AppSession
        let carol: AppSession
        let mailbox: InMemoryMailbox

        var aliceID: ParticipantID { get throws { try #require(alice.enrolment?.identity.id) } }
        var bobID: ParticipantID { get throws { try #require(bob.enrolment?.identity.id) } }

        func settle() async throws {
            for _ in 0..<4 {
                try await alice.sync(through: mailbox)
                try await bob.sync(through: mailbox)
            }
        }
    }

    private func peopleWhoShareARoom() async throws -> World {
        let world = World(
            alice: TestSession.make(), bob: TestSession.make(), carol: TestSession.make(), mailbox: InMemoryMailbox())
        for (session, name) in [(world.alice, "Alice"), (world.bob, "Bob"), (world.carol, "Carol")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        let room = try await world.alice.createRoom(named: "Lanterns")
        let invite = try await world.alice.invite(
            joinerCode: await world.bob.joinerCode(through: world.mailbox), joining: room, through: world.mailbox)
        try await world.bob.redeem(inviteCode: try invite.encoded())
        try await world.settle()
        #expect(world.alice.roster(of: room).members.contains(try world.bobID))
        return world
    }

    @Test("A solo started from the list of people lets that person in without a code of theirs")
    func aSoloWithSomebodyKnownIsJoined() async throws {
        let world = try await peopleWhoShareARoom()
        let solo = try await world.alice.startSolo(with: try world.bobID)

        let invite = try await world.alice.invite(try world.bobID, joining: solo, through: world.mailbox)
        try await world.bob.redeem(inviteCode: try invite.encoded())
        try await world.settle()

        #expect(world.alice.roster(of: solo).members.contains(try world.bobID))
        #expect(world.bob.roster(of: solo).members.contains(try world.aliceID))
        let phrase = try #require(world.alice.phrase(for: invite.attestation))
        #expect(world.bob.phrase(for: invite.attestation) == phrase)
    }

    @Test("Somebody else who gets hold of the invitation cannot use it")
    func anInterceptedInvitationOpensForNobodyElse() async throws {
        let world = try await peopleWhoShareARoom()
        let solo = try await world.alice.startSolo(with: try world.bobID)
        let invite = try await world.alice.invite(try world.bobID, joining: solo, through: world.mailbox)

        await #expect(throws: MembershipError.malformedInvite) {
            try await world.carol.redeem(inviteCode: try invite.encoded())
        }
        #expect(world.carol.rooms.allSatisfy { $0.id != solo })
    }

    @Test("An opening that does not match what the invitation was signed over is not kept")
    func aWrongOpeningIsNotKept() async throws {
        let world = try await peopleWhoShareARoom()
        let solo = try await world.alice.startSolo(with: try world.bobID)
        let invite = try await world.alice.invite(try world.bobID, joining: solo, through: world.mailbox)
        let forged = Invite(attestation: invite.attestation, pair: invite.pair, opening: JoinCommitment.nonce())

        #expect(forged.verifiedOpening == nil)
        try await world.bob.redeem(inviteCode: try forged.encoded())
        try await world.settle()

        #expect(world.bob.nonce(opening: invite.attestation.joinerCommitment) == nil)
        #expect(!world.alice.roster(of: solo).members.contains(try world.bobID))
    }

    @Test("An opening in an invitation never replaces the one this phone made for its own code")
    func anInvitationCannotReplaceTheJoinersOwnOpening() async throws {
        let world = try await peopleWhoShareARoom()
        let room = try await world.alice.createRoom(named: "Second")
        let code = await world.bob.joinerCode(through: world.mailbox)
        let commitment = try JoinerCode.decoded(from: code).commitment
        let held = try #require(world.bob.nonce(opening: commitment))
        let invite = try await world.alice.invite(joinerCode: code, joining: room, through: world.mailbox)

        try await world.bob.redeem(
            inviteCode: try Invite(attestation: invite.attestation, pair: invite.pair, opening: JoinCommitment.nonce()).encoded())

        #expect(world.bob.nonce(opening: commitment) == held)
    }

    @Test("Nobody can be invited this way before this phone holds their key")
    func aStrangerCannotBeInvitedWithoutACode() async throws {
        let world = try await peopleWhoShareARoom()
        let room = try await world.alice.createRoom(named: "Third")
        let stranger = try #require(world.carol.enrolment?.identity.id)

        await #expect(throws: AppSessionError.noIdentity) {
            try await world.alice.invite(stranger, joining: room, through: world.mailbox)
        }
    }

    @Test("An invitation written before openings existed still decodes")
    func anOlderInvitationStillDecodes() async throws {
        let world = try await peopleWhoShareARoom()
        let room = try await world.alice.createRoom(named: "Fourth")
        let invite = try await world.alice.invite(
            joinerCode: await world.bob.joinerCode(through: world.mailbox), joining: room, through: world.mailbox)

        #expect(invite.opening == nil)
        #expect(try Invite.decoded(from: try invite.encoded()) == invite)
    }
}
