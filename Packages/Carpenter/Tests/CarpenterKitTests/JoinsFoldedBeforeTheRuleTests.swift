import Foundation
import Testing
import CarpenterKitTesting

@testable import CarpenterKit

@Suite("A join folded before the rule existed")
struct JoinsFoldedBeforeTheRuleTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let room = ConversationID.room(UUID())

    private func rendered(
        _ author: ParticipantID, _ type: PayloadType, hash: UInt8, at offset: TimeInterval = 0
    ) -> RenderedEntry {
        RenderedEntry(
            id: EntryHash(rawValue: Data(repeating: hash, count: 32)), type: type, author: author,
            device: DeviceID(rawValue: WideID.of([])), wallTime: start.addingTimeInterval(offset),
            room: room, content: .text(""), editedAt: nil, replyingTo: nil, reactions: [:])
    }

    private func asTheOldBuildWroteIt(
        founder: Identity, joiner: Identity
    ) throws -> (roster: RoomRoster, invitation: MembershipAttestation) {
        var roster = RoomRoster(room: room)
        roster.apply(
            rendered(founder.id, .roomProfile, hash: 1),
            body: try Payload.roomProfile(name: "Hangar 7"))
        let invitation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: founder, at: start)
        roster.apply(
            rendered(founder.id, .joinRequest, hash: 2, at: 60),
            body: try Payload.joinRequest(invitation))
        return (roster, invitation)
    }

    @Test("Somebody who joined under the old rule is no longer counted")
    func theOldJoinNoLongerCounts() throws {
        let founder = Identity.generate()
        let joiner = Identity.generate()
        let (roster, _) = try asTheOldBuildWroteIt(founder: founder, joiner: joiner)

        #expect(!roster.members.contains(joiner.id))
        #expect(roster.members == [founder.id])
        #expect(roster.invited.contains(joiner.id))
        #expect(!roster.confirmed.contains(joiner.id))
    }

    @Test("Nobody is told they were removed, because nobody was")
    func itIsNotARemoval() throws {
        let founder = Identity.generate()
        let joiner = Identity.generate()
        let (roster, _) = try asTheOldBuildWroteIt(founder: founder, joiner: joiner)

        #expect(roster.removal(of: joiner.id) == nil)
        #expect(roster.departure(of: joiner.id) == nil)
        #expect(roster.mayWrite(joiner.id), "an old join was folded as a removal")
        #expect(roster.absent.isEmpty)
    }

    @Test("Confirming the same invitation puts them back")
    func confirmingRestoresThem() throws {
        let founder = Identity.generate()
        let joiner = Identity.generate()
        var (roster, invitation) = try asTheOldBuildWroteIt(founder: founder, joiner: joiner)

        roster.apply(
            rendered(founder.id, .joinConfirmed, hash: 3, at: 120),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: invitation, by: joiner)))

        #expect(roster.members.contains(joiner.id))
    }

    @Test("The transcript of an old join says invited, and does not say arrived")
    func theTranscriptSaysWhatHappened() throws {
        let founder = Identity.generate()
        let joiner = Identity.generate()
        let (_, invitation) = try asTheOldBuildWroteIt(founder: founder, joiner: joiner)

        var author = Author()
        let entries = [
            try author.append(try Payload.roomProfile(name: "Hangar 7"), at: start, room: room),
            try author.append(
                try Payload.joinRequest(invitation), at: start.addingTimeInterval(60), room: room),
        ]
        let projection = Projection(
            viewer: author.identity.id, rendered: Fold.render(entries, using: author.chain))
        let kinds = projection.transcript(
            in: room, opening: { rendered in
                entries.first { $0.hash == rendered.id }?.opened(using: author.chain)
            }
        ).compactMap { entry -> RoomNotice.Kind? in
            if case .notice(let notice) = entry { return notice.kind }
            return nil
        }

        #expect(kinds.contains { if case .invited = $0 { return true } else { return false } })
        #expect(
            !kinds.contains { if case .confirmed = $0 { return true } else { return false } },
            "a room announced an arrival its log has no record of")
    }
}
