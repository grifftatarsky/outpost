import Foundation
import Testing
import CarpenterKitTesting

@testable import CarpenterKit

@Suite("The joiner's confirmation, on the wire")
struct JoinConfirmationWireTests {
    private let now = Date(timeIntervalSince1970: 1_786_635_000)

    private func invitation() throws -> (
        attestation: MembershipAttestation, inviter: Identity, joiner: Identity
    ) {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        let attestation = try TestInvite.issue(
            joining: RoomID(), joinerKeys: joiner.publicKeys, by: inviter, at: now)
        return (attestation, inviter, joiner)
    }

    @Test("It is classified, exactly once, as plumbing")
    func classified() {
        #expect(PayloadType.allKnown.contains(.joinConfirmed))
        #expect(PayloadType.plumbing.contains(.joinConfirmed))
        #expect(PayloadType.joinConfirmed.rawValue == 21)
    }

    @Test("The roster is offered the entries it reacts to")
    func rosterShapingNamesIt() {
        #expect(RoomRoster.rosterShaping.contains(.joinConfirmed))
        #expect(RoomRoster.rosterShaping.isSubset(of: PayloadType.allKnown))
    }

    @Test("A confirmation the joiner signed verifies against the invitation")
    func signedByTheJoinerVerifies() throws {
        let (attestation, _, joiner) = try invitation()
        let body = try JoinConfirmedBody.signed(confirming: attestation, by: joiner)

        #expect(throws: Never.self) { try body.verify(confirming: attestation) }
        #expect(body.joiner == attestation.joiner)
        #expect(body.invitation == attestation.signature)
    }

    @Test("A relay cannot sign in the joiner's name")
    func theRelayCannotForgeIt() throws {
        let (attestation, inviter, _) = try invitation()
        let forged = JoinConfirmedBody(
            invitation: attestation.signature,
            joiner: attestation.joiner,
            nonce: TestInvite.nonce(for: attestation),
            signature: try inviter.sign(
                JoinConfirmedBody.signedBytes(
                    invitation: attestation.signature, joiner: attestation.joiner,
                    nonce: TestInvite.nonce(for: attestation))))

        #expect(throws: MembershipError.self) { try forged.verify(confirming: attestation) }
    }

    @Test("A stranger cannot sign in the joiner's name either")
    func aStrangerCannotForgeIt() throws {
        let (attestation, _, _) = try invitation()
        let stranger = Identity.generate()
        let forged = JoinConfirmedBody(
            invitation: attestation.signature,
            joiner: attestation.joiner,
            nonce: TestInvite.nonce(for: attestation),
            signature: try stranger.sign(
                JoinConfirmedBody.signedBytes(
                    invitation: attestation.signature, joiner: attestation.joiner,
                    nonce: TestInvite.nonce(for: attestation))))

        #expect(throws: MembershipError.self) { try forged.verify(confirming: attestation) }
    }

    @Test("A signature cannot be lifted onto another invitation")
    func noReplayOntoAnotherInvitation() throws {
        let (first, _, joiner) = try invitation()
        let body = try JoinConfirmedBody.signed(confirming: first, by: joiner)

        let inviter = Identity.generate()
        let second = try TestInvite.issue(
            joining: RoomID(), joinerKeys: joiner.publicKeys, by: inviter, at: now)

        #expect(throws: MembershipError.self) { try body.verify(confirming: second) }
    }

    @Test("A confirmation naming somebody else is refused")
    func noSwappingTheJoiner() throws {
        let (attestation, _, joiner) = try invitation()
        let signed = try JoinConfirmedBody.signed(confirming: attestation, by: joiner)
        let somebodyElse = Identity.generate()
        let swapped = JoinConfirmedBody(
            invitation: signed.invitation, joiner: somebodyElse.id, signature: signed.signature)

        #expect(throws: MembershipError.self) { try swapped.verify(confirming: attestation) }
    }

    @Test("It survives a round trip through the payload")
    func roundTrips() throws {
        let (attestation, _, joiner) = try invitation()
        let body = try JoinConfirmedBody.signed(confirming: attestation, by: joiner)
        let payload = try Payload.joinConfirmed(body)

        #expect(payload.type == .joinConfirmed)
        #expect(try payload.decode(JoinConfirmedBody.self) == body)
    }

    @Test("It carries fallback text, because an older build will draw it")
    func carriesFallbackText() throws {
        let (attestation, _, joiner) = try invitation()
        let payload = try Payload.joinConfirmed(
            try JoinConfirmedBody.signed(confirming: attestation, by: joiner))

        let fallback = try #require(payload.fallbackText)
        #expect(!fallback.isEmpty)
    }

    @Test("The fold renders it as itself, not as somebody's words")
    func foldsAsPlumbing() throws {
        let (attestation, _, joiner) = try invitation()
        let payload = try Payload.joinConfirmed(
            try JoinConfirmedBody.signed(confirming: attestation, by: joiner))

        var relay = Author()
        let entry = try relay.append(payload, at: now)
        let rendered = try #require(Fold.render([entry], using: relay.chain).first)

        #expect(rendered.type == PayloadType.joinConfirmed)
        guard case .unrenderable(let type, let fallback) = rendered.content else {
            Issue.record("a confirmation folded as something a member said")
            return
        }
        #expect(type == PayloadType.joinConfirmed)
        #expect(fallback != nil)
    }
}
