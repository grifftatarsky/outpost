@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Sharing a name", .serialized)
struct SharingTests {
    private func joined() async throws -> (alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox) {
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
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        return (alice, bob, mailbox)
    }

    private func settle(_ a: AppSession, _ b: AppSession, _ mailbox: InMemoryMailbox) async throws {
        for _ in 0..<2 {
            try await a.sync(through: mailbox)
            try await b.sync(through: mailbox)
        }
    }

    @Test("A member sees their own name; nobody else does until they share it")
    func nameStaysHomeUntilShared() async throws {
        let (alice, bob, mailbox) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)

        #expect(alice.viewer.displayName == "Alice", "the member's own screen must show the name")
        #expect(!alice.sharesName, "sharing is off until chosen")

        await bob.setShowsOthersNames(true)
        try await settle(alice, bob, mailbox)
        #expect(bob.member(aliceID).isPlaceholder, "a name that was never shared was drawn")

        await alice.setSharesName(true)
        try await settle(alice, bob, mailbox)
        #expect(bob.member(aliceID).displayName == "Alice")
    }

    @Test("A shared name is still a code to somebody who does not receive names")
    func receivingOffHidesASharedName() async throws {
        let (alice, bob, mailbox) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)

        await alice.setSharesName(true)
        try await settle(alice, bob, mailbox)
        #expect(bob.member(aliceID).isPlaceholder, "receiving is off by default")

        await bob.setShowsOthersNames(true)
        #expect(bob.member(aliceID).displayName == "Alice", "the entry was there all along")

        await bob.setShowsOthersNames(false)
        #expect(bob.member(aliceID).isPlaceholder, "turning it off applies at once")
    }

    @Test("Turning sharing off takes nothing back")
    func sharingOffKeepsWhatRoomsHave() async throws {
        let (alice, bob, mailbox) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        await bob.setShowsOthersNames(true)
        await alice.setSharesName(true)
        try await settle(alice, bob, mailbox)
        #expect(bob.member(aliceID).displayName == "Alice")

        await alice.setSharesName(false)
        try await settle(alice, bob, mailbox)
        #expect(bob.member(aliceID).displayName == "Alice", "an entry is forever; the switch says so")
    }

    @Test("A rename while sharing is off reaches only the member's own devices")
    func renameWhileNotSharingWritesNothing() async throws {
        let (alice, bob, mailbox) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        await bob.setShowsOthersNames(true)

        try await alice.setDisplayName("Alicia")
        try await settle(alice, bob, mailbox)
        #expect(alice.viewer.displayName == "Alicia")
        #expect(bob.member(aliceID).isPlaceholder, "a rename must not leak a name that was never shared")
    }
}
