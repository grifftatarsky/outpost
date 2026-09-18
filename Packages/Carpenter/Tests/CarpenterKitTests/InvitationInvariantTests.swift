@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("What a join does, pinned", .serialized)
struct InvitationInvariantTests {
    private func paired() async throws -> (a: AppSession, b: AppSession, mailbox: InMemoryMailbox, room: RoomID) {
        let mailbox = InMemoryMailbox()
        let a = TestSession.make()
        let b = TestSession.make()
        await a.load()
        await b.load()
        try await a.createIdentity(displayName: "Ada")
        try await b.createIdentity(displayName: "Bo")
        let room = try await a.createRoom(named: "Hangar")
        return (a, b, mailbox, room)
    }

    private func settle(_ everyone: [AppSession], _ mailbox: InMemoryMailbox, rounds: Int = 4) async throws {
        for _ in 0..<rounds {
            for s in everyone { try await s.sync(through: mailbox) }
        }
    }

    @Test("A join turns the key once")
    func oneEpochTurnPerJoin() async throws {
        let (a, b, mailbox, room) = try await paired()
        let before = a.epochsHeld(in: room)

        let invite = try await a.invite(joinerCode: b.identityCode(), joining: room, mailbox: nil)
        try await b.redeem(inviteCode: try invite.encoded())
        try await a.sync(through: mailbox)
        try await b.accept(invite.attestation, from: try #require(a.enrolment?.identity.publicKeys))
        try await settle([a, b], mailbox)

        #expect(a.epochsHeld(in: room) == before + 1)
    }

    @Test("The inviter keeps the joiner's keys across a relaunch")
    func joinerKeysSurviveARelaunch() async throws {
        let (a, b, mailbox, room) = try await paired()
        let bID = try #require(b.enrolment?.identity.id)

        let invite = try await a.invite(joinerCode: b.identityCode(), joining: room, mailbox: nil)
        try await b.redeem(inviteCode: try invite.encoded())
        try await a.sync(through: mailbox)
        try await b.accept(invite.attestation, from: try #require(a.enrolment?.identity.publicKeys))
        try await settle([a, b], mailbox)

        #expect(a.knowsIdentity(of: bID), "the inviter never learned the joiner's keys")
    }

    @Test("mayWrite says nothing about somebody who was never in the room")
    func mayWriteIsNotTheAdmissionGate() async throws {
        let (a, b, _, room) = try await paired()
        let bID = try #require(b.enrolment?.identity.id)

        let roster = a.roster(of: room)
        #expect(!roster.members.contains(bID), "nobody has joined yet")
        #expect(roster.mayWrite(bID), "mayWrite is about removal, not about admission")
    }

    @Test("Tightening the rule evicts nobody, before or after a join")
    func tighteningEvictsNobody() async throws {
        let (a, b, mailbox, room) = try await paired()
        let bID = try #require(b.enrolment?.identity.id)

        let invite = try await a.invite(joinerCode: b.identityCode(), joining: room, mailbox: nil)
        try await b.redeem(inviteCode: try invite.encoded())
        try await a.sync(through: mailbox)
        try await b.accept(invite.attestation, from: try #require(a.enrolment?.identity.publicKeys))
        try await settle([a, b], mailbox)
        #expect(a.roster(of: room).members.contains(bID))

        try await a.setAccess(.unanimous, in: room)
        try await settle([a, b], mailbox)
        #expect(a.roster(of: room).members.contains(bID), "tightening the rule put somebody out")
    }
}
