@testable import CarpenterKit
import Foundation
import Testing
import CarpenterKitTesting

@Suite("A room that asks for more approvals than it has members")
struct ApprovalThresholdTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let room = RoomID()

    private func rendered(
        _ author: ParticipantID, _ type: PayloadType, hash: UInt8
    ) -> RenderedEntry {
        RenderedEntry(
            id: EntryHash(rawValue: Data(repeating: hash, count: 32)),
            type: type,
            author: author,
            device: DeviceID(rawValue: WideID.of([])),
            wallTime: start,
            room: room,
            content: .text(""),
            editedAt: nil,
            replyingTo: nil,
            reactions: [:]
        )
    }

    private func room(
        threshold: Int, founder: Identity, others: [Identity], joiner: Identity,
        admittedBy admitters: [Identity], refusedBy refusers: [Identity] = []
    ) throws -> RoomRoster {
        var roster = RoomRoster(room: room)
        var hash: UInt8 = 1
        func next() -> UInt8 { defer { hash += 1 }; return hash }

        roster.apply(
            rendered(founder.id, .roomProfile, hash: next()),
            body: try Payload.roomProfile(name: "Hangar 7"))
        roster.set(access: .atLeast(threshold), by: founder.id)

        for other in others {
            let invite = try TestInvite.issue(
                joining: self.room, joinerKeys: other.publicKeys, by: founder, at: start)
            roster.apply(
                rendered(founder.id, .joinRequest, hash: next()),
                body: try Payload.joinRequest(invite))
            roster.apply(
                rendered(founder.id, .joinConfirmed, hash: next()),
                body: try Payload.joinConfirmed(
                    try JoinConfirmedBody.signed(confirming: invite, by: other)))
            for member in [founder] + others.prefix(while: { $0.id != other.id }) {
                roster.apply(
                    rendered(member.id, .admission, hash: next()),
                    body: try Payload.admission(of: other.id, admitted: true))
            }
        }

        let invite = try TestInvite.issue(
            joining: self.room, joinerKeys: joiner.publicKeys, by: founder, at: start)
        roster.apply(
            rendered(founder.id, .joinRequest, hash: next()),
            body: try Payload.joinRequest(invite))
        roster.apply(
            rendered(founder.id, .joinConfirmed, hash: next()),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: invite, by: joiner)))
        for refuser in refusers {
            roster.apply(
                rendered(refuser.id, .admission, hash: next()),
                body: try Payload.admission(of: joiner.id, admitted: false))
        }
        for admitter in admitters {
            roster.apply(
                rendered(admitter.id, .admission, hash: next()),
                body: try Payload.admission(of: joiner.id, admitted: true))
        }
        return roster
    }

    @Test("A room asking for four, holding one, admits on that one")
    func clampsToTheMembersThereAre() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        let roster = try room(
            threshold: 4, founder: alice, others: [], joiner: joiner, admittedBy: [alice])

        #expect(roster.effectiveThreshold(4, admitting: joiner.id) == 1)
        #expect(roster.members.contains(joiner.id), "a room of one asking for four let nobody in")
    }

    @Test("While it is clamped, one member withholding is enough to stop a join")
    func clampedMeansEverybody() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let joiner = Identity.generate()

        let onlyAlice = try room(
            threshold: 4, founder: alice, others: [bob], joiner: joiner, admittedBy: [alice])
        #expect(
            onlyAlice.effectiveThreshold(4, admitting: joiner.id) == 1,
            "alice invited them, so bob is the only one who can agree")
        #expect(
            !onlyAlice.members.contains(joiner.id),
            "the person who invited them counted as the agreement")

        let both = try room(
            threshold: 4, founder: alice, others: [bob], joiner: joiner, admittedBy: [alice, bob])
        #expect(both.members.contains(joiner.id))
    }

    @Test("Once the room is big enough the chosen number is what is required")
    func stopsClampingWhenTheRoomGrows() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let carol = Identity.generate()
        let joiner = Identity.generate()

        let two = try room(
            threshold: 2, founder: alice, others: [bob, carol], joiner: joiner,
            admittedBy: [bob, carol])

        #expect(
            two.effectiveThreshold(2, admitting: joiner.id) == 2,
            "three members, one of them the inviter, asked for two")
        #expect(
            two.members.contains(joiner.id),
            "two of the three admitted under a threshold of two and it was refused")

        let counting = try room(
            threshold: 2, founder: alice, others: [bob, carol], joiner: joiner,
            admittedBy: [alice, bob])
        #expect(
            !counting.members.contains(joiner.id),
            "the inviter's own agreement was counted towards the two")
    }

    @Test("Changing your mind counts, in both directions")
    func decisionsReplaceEachOther() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let joiner = Identity.generate()

        let refusedThenAdmitted = try room(
            threshold: 4, founder: alice, others: [bob], joiner: joiner,
            admittedBy: [alice, bob], refusedBy: [bob])

        #expect(
            refusedThenAdmitted.members.contains(joiner.id),
            "a withdrawn refusal went on blocking")
    }

    @Test("A nonsensical threshold still requires somebody to agree")
    func neverAdmitsOnNobody() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        for nonsense in [0, -1, Int.min] {
            let roster = try room(
                threshold: nonsense, founder: alice, others: [], joiner: joiner, admittedBy: [])
            #expect(
                roster.effectiveThreshold(nonsense, admitting: joiner.id) >= 1, "\(nonsense)")
            #expect(
                !roster.members.contains(joiner.id),
                "a threshold of \(nonsense) admitted somebody nobody agreed to")
        }
    }

    @Test("The threshold a room will actually apply is readable from outside")
    func theRuleIsReadable() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let joiner = Identity.generate()

        let roster = try room(
            threshold: 5, founder: alice, others: [bob], joiner: joiner, admittedBy: [])

        #expect(
            roster.effectiveThreshold(5, admitting: joiner.id) == 1,
            "alice invited them, so the room can only ever ask bob")
        #expect(roster.effectiveThreshold(1, admitting: joiner.id) == 1)
    }
}
