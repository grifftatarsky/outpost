import Foundation
import Testing
import CarpenterKitTesting

@testable import CarpenterKit

@Suite("An invitation is an offer")
struct InvitationIsAnOfferTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let room = ConversationID.room(UUID())

    private func rendered(
        _ author: ParticipantID, _ type: PayloadType, hash: UInt8
    ) -> RenderedEntry {
        RenderedEntry(
            id: EntryHash(rawValue: Data(repeating: hash, count: 32)),
            type: type, author: author, device: DeviceID(rawValue: WideID.of([])),
            wallTime: start, room: room, content: .text(""),
            editedAt: nil, replyingTo: nil, reactions: [:])
    }

    private func founded(by founder: Identity, access: RoomAccess = .open) throws -> RoomRoster {
        var roster = RoomRoster(room: room)
        roster.apply(
            rendered(founder.id, .roomProfile, hash: 1),
            body: try Payload.roomProfile(name: "Hangar 7"))
        if access != .open {
            roster.apply(
                rendered(founder.id, .roomAccess, hash: 2),
                body: try Payload.roomAccess(access))
        }
        return roster
    }

    private func invite(
        _ joiner: Identity, to roster: inout RoomRoster, by inviter: Identity, hash: UInt8
    ) throws -> MembershipAttestation {
        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)
        roster.apply(
            rendered(inviter.id, .joinRequest, hash: hash),
            body: try Payload.joinRequest(attestation))
        return attestation
    }

    private func confirm(
        _ attestation: MembershipAttestation, by joiner: Identity,
        to roster: inout RoomRoster, relayedBy inviter: Identity, hash: UInt8
    ) throws {
        roster.apply(
            rendered(inviter.id, .joinConfirmed, hash: hash),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: attestation, by: joiner)))
    }

    @Test("An invitation alone admits nobody, even to an open room")
    func anInvitationAloneAdmitsNobody() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        _ = try invite(joiner, to: &roster, by: inviter, hash: 3)

        #expect(!roster.members.contains(joiner.id), "an invitation put somebody in the room")
        #expect(roster.members.contains(inviter.id), "the founder is still in it")
    }

    @Test("A confirmed invitation admits, in an open room")
    func confirmationAdmits() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let attestation = try invite(joiner, to: &roster, by: inviter, hash: 3)
        try confirm(attestation, by: joiner, to: &roster, relayedBy: inviter, hash: 4)

        #expect(roster.members.contains(joiner.id))
    }

    @Test("A confirmation the joiner did not sign admits nobody")
    func aForgedConfirmationAdmitsNobody() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let attestation = try invite(joiner, to: &roster, by: inviter, hash: 3)
        let forged = JoinConfirmedBody(
            invitation: attestation.signature,
            joiner: attestation.joiner,
            nonce: TestInvite.nonce(for: attestation),
            signature: try inviter.sign(
                JoinConfirmedBody.signedBytes(
                    invitation: attestation.signature, joiner: attestation.joiner,
                    nonce: TestInvite.nonce(for: attestation))))
        roster.apply(
            rendered(inviter.id, .joinConfirmed, hash: 4),
            body: try Payload.joinConfirmed(forged))

        #expect(!roster.members.contains(joiner.id), "a forged confirmation admitted somebody")
    }

    @Test("A confirmation for an invitation this room never saw admits nobody")
    func aConfirmationWithNoInvitationAdmitsNobody() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let unseen = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)
        try confirm(unseen, by: joiner, to: &roster, relayedBy: inviter, hash: 4)

        #expect(!roster.members.contains(joiner.id))
    }

    @Test("In a founder room, confirming is not enough on its own")
    func confirmingIsNotApproval() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter, access: .founder)

        let attestation = try invite(joiner, to: &roster, by: inviter, hash: 3)
        try confirm(attestation, by: joiner, to: &roster, relayedBy: inviter, hash: 4)
        #expect(!roster.members.contains(joiner.id), "confirming let somebody past the founder")

        roster.apply(
            rendered(inviter.id, .admission, hash: 5),
            body: try Payload.admission(of: joiner.id, admitted: true))
        #expect(roster.members.contains(joiner.id))
    }

    @Test("An approval before a confirmation still waits for the confirmation")
    func approvalBeforeConfirmationStillWaits() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter, access: .founder)

        let attestation = try invite(joiner, to: &roster, by: inviter, hash: 3)
        roster.apply(
            rendered(inviter.id, .admission, hash: 4),
            body: try Payload.admission(of: joiner.id, admitted: true))
        #expect(!roster.members.contains(joiner.id), "approval alone admitted somebody")

        try confirm(attestation, by: joiner, to: &roster, relayedBy: inviter, hash: 5)
        #expect(roster.members.contains(joiner.id))
    }

    @Test("The founder is still established by founding")
    func theFounderIsUnaffected() throws {
        let founder = Identity.generate()
        let roster = try founded(by: founder)
        #expect(roster.members.contains(founder.id))
    }

    @Test("The roster can say who has confirmed and is still waiting")
    func waitingIsItsOwnState() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter, access: .founder)

        let attestation = try invite(joiner, to: &roster, by: inviter, hash: 3)
        #expect(roster.invited.contains(joiner.id))
        #expect(!roster.confirmed.contains(joiner.id))

        try confirm(attestation, by: joiner, to: &roster, relayedBy: inviter, hash: 4)
        #expect(roster.confirmed.contains(joiner.id))
        #expect(!roster.members.contains(joiner.id), "confirmed is not the same as in")
    }
}
