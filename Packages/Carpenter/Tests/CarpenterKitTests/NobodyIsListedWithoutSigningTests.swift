@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Nobody is listed in a room without signing for it")
struct NobodyIsListedWithoutSigningTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private struct Room {
        var roster: RoomRoster
        var hash: UInt8 = 1
        let start: Date

        mutating func write(_ author: Identity, _ type: PayloadType, _ body: Payload) {
            roster.apply(
                RenderedEntry(
                    id: EntryHash(rawValue: Data(repeating: hash, count: 32)), type: type, author: author.id,
                    device: DeviceID(rawValue: WideID.of([])), wallTime: start, room: roster.room,
                    content: .text(""), editedAt: nil, replyingTo: nil, reactions: [:]),
                body: body)
            hash &+= 1
        }
    }

    private func roomWithMallory() throws -> (room: Room, founder: Identity, mallory: Identity) {
        let (founder, mallory) = (Identity.generate(), Identity.generate())
        let (id, profile) = try TestFounding.room(by: founder.id)
        var room = Room(roster: RoomRoster(room: id), start: start)
        room.write(founder, .roomProfile, profile)
        let invite = try TestInvite.issue(joining: id, joinerKeys: mallory.publicKeys, by: founder, at: start)
        room.write(founder, .joinRequest, try Payload.joinRequest(invite))
        room.write(founder, .joinConfirmed, try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: mallory)))
        return (room, founder, mallory)
    }

    private func naming(
        _ named: ParticipantID, withTheKeysOf holder: Identity, by inviter: Identity, in room: RoomID
    ) throws -> (invitation: MembershipAttestation, confirmation: JoinConfirmedBody) {
        var invitation = try TestInvite.issue(joining: room, joinerKeys: holder.publicKeys, by: inviter, at: start)
        invitation.joiner = named
        invitation.signature = try inviter.sign(invitation.signingPayload)
        let nonce = TestInvite.nonce(for: invitation)
        let confirmation = JoinConfirmedBody(
            invitation: invitation.signature, joiner: named, nonce: nonce,
            signature: try holder.sign(
                JoinConfirmedBody.signedBytes(invitation: invitation.signature, joiner: named, nonce: nonce)))
        return (invitation, confirmation)
    }

    @Test("An invitation that names one person and carries somebody else's keys lists nobody")
    func aNameNeedsItsOwnKeys() throws {
        var (room, _, mallory) = try roomWithMallory()
        let (griff, puppet) = (Identity.generate(), Identity.generate())
        let (invitation, confirmation) = try naming(griff.id, withTheKeysOf: puppet, by: mallory, in: room.roster.room)

        room.write(mallory, .joinRequest, try Payload.joinRequest(invitation))
        room.write(mallory, .joinConfirmed, try Payload.joinConfirmed(confirmation))

        #expect(!room.roster.members.contains(griff.id), "a member listed somebody in the room who never signed anything")
        #expect(room.roster.requests[griff.id] == nil)
    }

    @Test("An invitation its inviter did not sign is not an invitation")
    func anInvitationIsSigned() throws {
        var (room, _, mallory) = try roomWithMallory()
        let joiner = Identity.generate()
        var invitation = try TestInvite.issue(joining: room.roster.room, joinerKeys: joiner.publicKeys, by: mallory, at: start)
        invitation.expiresAt = invitation.expiresAt.addingTimeInterval(60)

        room.write(mallory, .joinRequest, try Payload.joinRequest(invitation))
        room.write(
            mallory, .joinConfirmed, try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invitation, by: joiner)))

        #expect(room.roster.requests[joiner.id] == nil, "an invitation whose signature does not match was taken")
        #expect(!room.roster.members.contains(joiner.id))
    }

    @Test("The room does not announce somebody who never signed for it")
    func theTranscriptSaysNothingOfThem() throws {
        var (founder, room, profile) = try Author.founding()
        var mallory = Author(chain: founder.chain)
        let (griff, puppet) = (Identity.generate(), Identity.generate())
        let invite = try TestInvite.issue(joining: room, joinerKeys: mallory.identity.publicKeys, by: founder.identity, at: start)
        let (invitation, confirmation) = try naming(griff.id, withTheKeysOf: puppet, by: mallory.identity, in: room)
        let entries = [
            try founder.append(profile, at: start, room: room),
            try founder.append(try Payload.joinRequest(invite), at: start + 1, room: room),
            try founder.append(
                try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: mallory.identity)),
                at: start + 2, room: room),
            try mallory.append(try Payload.joinRequest(invitation), at: start + 3, room: room),
            try mallory.append(try Payload.joinConfirmed(confirmation), at: start + 4, room: room),
        ]

        let projected = Projection(viewer: founder.identity.id, rendered: LogRenderer.render(entries, using: founder.chain))
        let named = projected.transcript(in: room, opening: { rendered in
            entries.first { $0.hash == rendered.id }?.opened(using: founder.chain)
        }).compactMap { item -> ParticipantID? in
            guard case .notice(let notice) = item else { return nil }
            switch notice.kind {
            case .invited(let who, _), .confirmed(let who): return who.id
            default: return nil
            }
        }

        #expect(named.contains(mallory.identity.id), "precondition: the room announces a real invitation")
        #expect(!named.contains(griff.id), "the room announced somebody who never signed for it")
    }
}
