import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@MainActor
@Suite("Joining a room from today", .serialized)
struct JoiningFromTodayTests {
    private func settle(_ sessions: [AppSession], _ mailbox: InMemoryMailbox, rounds: Int = 6) async throws {
        for _ in 0..<rounds {
            for session in sessions { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func words(_ session: AppSession, in room: RoomID) -> [String] {
        session.messages(in: room).map(\.body)
    }

    @Test("What was said before they arrived stays sealed, and what comes after does not")
    func forwardOnly() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("before bob", to: room)

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil, sharingHistory: false)
        #expect(!invite.attestation.sharesHistory)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await settle([alice, bob], mailbox)

        try await alice.send("after bob", to: room)
        try await settle([alice, bob], mailbox)

        #expect(alice.roster(of: room).members.contains(try #require(bob.enrolment?.identity.id)))
        #expect(alice.roster(of: room).historyFloor(of: try #require(bob.enrolment?.identity.id)) != nil)

        let seen = words(bob, in: room)
        #expect(seen.contains("after bob"), "the new member cannot read what was said after they joined")
        #expect(!seen.contains("before bob"), "the new member read what was said before they arrived")

        #expect(
            bob.missingHistory(in: room).isEmpty,
            "the new member is asking for history the room will never give them")
        #expect(
            bob.repairStatus(of: room) == nil,
            "the new member was shown a repair they can never finish")
    }

    @Test("A full-history invitation still hands over everything")
    func fullHistoryStillWorks() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("before bob", to: room)

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        #expect(invite.attestation.sharesHistory)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await settle([alice, bob], mailbox)
        try await alice.send("after bob", to: room)
        try await settle([alice, bob], mailbox)

        let seen = words(bob, in: room)
        #expect(seen.contains("before bob"))
        #expect(seen.contains("after bob"))
        #expect(alice.roster(of: room).historyFloor(of: try #require(bob.enrolment?.identity.id)) == nil)
    }

    @Test("Somebody who joins from today still sees who is in the room")
    func theRoomIsRestated() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        await alice.load()
        await bob.load()
        await carol.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")

        let room = try await alice.createRoom(named: "Hangar 7")
        let first = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try first.encoded())
        try await settle([alice, bob], mailbox)

        let second = try await alice.invite(
            joinerCode: carol.identityCode(), joining: room, mailbox: nil, sharingHistory: false)
        try await carol.redeem(inviteCode: try second.encoded())
        try await settle([alice, bob, carol], mailbox, rounds: 8)

        let aliceID = try #require(alice.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)
        let carolID = try #require(carol.enrolment?.identity.id)

        let seen = carol.roster(of: room).members
        #expect(seen.contains(aliceID), "a member who joined from today cannot see who invited them")
        #expect(seen.contains(bobID), "a member who joined from today cannot see the other member")
        #expect(seen.contains(carolID))
    }

    @Test("An invitation written before today still shares everything")
    func anOlderInvitationSharesHistory() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let room = RoomID()
        let attestation = try MembershipAttestation.issue(
            joining: room, joinerKeys: bob.publicKeys, by: alice,
            at: Date(timeIntervalSince1970: 1_786_635_000))

        var without = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(attestation)) as! [String: Any]
        without.removeValue(forKey: "sharesHistory")
        let older = try JSONSerialization.data(withJSONObject: without)

        let decoded = try JSONDecoder().decode(MembershipAttestation.self, from: older)
        #expect(decoded.sharesHistory, "an invitation from an older build stopped sharing history")
        #expect(
            (try? decoded.verify(against: alice.publicKeys, at: attestation.issuedAt)) != nil,
            "adding the field changed the bytes an older invitation was signed over")
    }
}
