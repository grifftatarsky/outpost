import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("Being asked about people you meet", .serialized)
struct OutpostReviewOfferTests {
    private func joined() async throws -> (
        alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox, room: RoomID
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
        for _ in 0..<6 {
            for s in [alice, bob] { try await s.sync(through: mailbox, media: mailbox) }
        }
        return (alice, bob, mailbox, room)
    }

    @Test("On by default, because it discloses nothing")
    func onByDefault() async throws {
        let (alice, _, _, room) = try await joined()
        #expect(alice.offersOutpostReview)
        #expect(alice.outpostReview(in: room) != nil)
    }

    @Test("Off, a new room-mate raises nothing")
    func offAsksNothing() async throws {
        let (alice, _, _, room) = try await joined()
        await alice.setOffersOutpostReview(false)
        #expect(alice.outpostReview(in: room) == nil)
    }

    @Test("Turning it off lets nobody in and puts nobody out")
    func itGrantsNothing() async throws {
        let (alice, bob, mailbox, room) = try await joined()
        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        for _ in 0..<6 {
            for s in [alice, bob] { try await s.sync(through: mailbox, media: mailbox) }
        }
        #expect(alice.outpostReaders() == [bobID])

        await alice.setOffersOutpostReview(false)
        #expect(alice.outpostReaders() == [bobID], "turning the question off took access away")
        #expect(alice.outpostReview(in: room) == nil)
    }

    @Test("With Outposts off there is nothing to ask about")
    func offOutpostsAskNothing() async throws {
        let (alice, _, _, room) = try await joined()
        await alice.setOutpostConsent(.off)
        #expect(alice.outpostReview(in: room) == nil)
    }
}
