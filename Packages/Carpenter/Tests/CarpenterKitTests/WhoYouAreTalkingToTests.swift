import Foundation
import Testing
import CarpenterKitTesting

@testable import CarpenterKit

@Suite("Who you are talking to")
struct WhoYouAreTalkingToTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let room = ConversationID.room(UUID())

    private func rendered(
        _ author: ParticipantID, _ type: PayloadType, hash: UInt8, at offset: TimeInterval = 0
    ) -> RenderedEntry {
        RenderedEntry(
            id: EntryHash(rawValue: Data(repeating: hash, count: 32)), type: type, author: author,
            device: DeviceID(rawValue: WideID.of([])), wallTime: start.addingTimeInterval(offset),
            conversation: room, content: .text(""), editedAt: nil, replyingTo: nil, reactions: [:])
    }

    private func founded(by founder: Identity, access: RoomAccess = .open) throws -> RoomRoster {
        var roster = RoomRoster(room: room)
        roster.apply(
            rendered(founder.id, .roomProfile, hash: 1),
            body: try Payload.roomProfile(name: "Hangar 7"))
        if access != .open { roster.set(access: access, by: founder.id) }
        return roster
    }

    @Test("The room records when a confirmation landed in it")
    func theRoomRemembersWhen() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let invite = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)
        roster.apply(
            rendered(inviter.id, .joinRequest, hash: 2), body: try Payload.joinRequest(invite))
        roster.apply(
            rendered(inviter.id, .joinConfirmed, hash: 3, at: 90),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: invite, by: joiner)))

        #expect(roster.confirmedAt(joiner.id) == start.addingTimeInterval(90))
        #expect(roster.confirmedAt(inviter.id) == nil, "the founder never confirmed anything")
    }

    @Test("A second confirmation does not move the date")
    func theFirstOneStands() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let invite = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)
        roster.apply(
            rendered(inviter.id, .joinRequest, hash: 2), body: try Payload.joinRequest(invite))
        let confirmation = try Payload.joinConfirmed(
            try JoinConfirmedBody.signed(confirming: invite, by: joiner))

        roster.apply(rendered(inviter.id, .joinConfirmed, hash: 4, at: 200), body: confirmation)
        roster.apply(rendered(inviter.id, .joinConfirmed, hash: 3, at: 90), body: confirmation)

        #expect(
            roster.confirmedAt(joiner.id) == start.addingTimeInterval(90),
            "the later copy of the same confirmation moved the date")
    }

    @Test("A confirmation that folds to nothing leaves no date")
    func aForgeryLeavesNoDate() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let invite = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)
        roster.apply(
            rendered(inviter.id, .joinRequest, hash: 2), body: try Payload.joinRequest(invite))
        let forged = JoinConfirmedBody(
            invitation: invite.signature,
            joiner: invite.joiner,
            signature: try inviter.sign(
                JoinConfirmedBody.signedBytes(
                    invitation: invite.signature, joiner: invite.joiner,
                    nonce: TestInvite.nonce(for: invite))))
        roster.apply(
            rendered(inviter.id, .joinConfirmed, hash: 3, at: 90),
            body: try Payload.joinConfirmed(forged))

        #expect(roster.confirmedAt(joiner.id) == nil)
        #expect(!roster.members.contains(joiner.id))
    }

    @Test("The room still holds the invitation somebody arrived on")
    func theInvitationOutlivesTheJoin() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let invite = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)
        roster.apply(
            rendered(inviter.id, .joinRequest, hash: 2), body: try Payload.joinRequest(invite))
        roster.apply(
            rendered(inviter.id, .joinConfirmed, hash: 3, at: 90),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: invite, by: joiner)))

        let held = try #require(roster.requests[joiner.id])
        #expect(held.testPhrase == invite.testPhrase)
        #expect(!held.testPhrase.isEmpty)
    }
}
