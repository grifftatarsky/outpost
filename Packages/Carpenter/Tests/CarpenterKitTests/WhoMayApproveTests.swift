import Foundation
import Testing
import CarpenterKitTesting

@testable import CarpenterKit

@Suite("Who may agree to an invitation")
struct WhoMayApproveTests {
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

    private func founded(by founder: Identity, alongside others: [Identity] = []) throws
        -> RoomRoster
    {
        var roster = RoomRoster(room: room)
        roster.apply(
            rendered(founder.id, .roomProfile, hash: 1),
            body: try Payload.roomProfile(name: "Hangar 7"))
        for (offset, member) in others.enumerated() {
            let attestation = try TestInvite.issue(
                joining: room, joinerKeys: member.publicKeys, by: founder, at: start)
            roster.apply(
                rendered(founder.id, .joinRequest, hash: UInt8(20 + offset)),
                body: try Payload.joinRequest(attestation))
            roster.apply(
                rendered(founder.id, .joinConfirmed, hash: UInt8(60 + offset)),
                body: try Payload.joinConfirmed(
                    try JoinConfirmedBody.signed(confirming: attestation, by: member)))
            roster.apply(
                rendered(founder.id, .admission, hash: UInt8(40 + offset)),
                body: try Payload.admission(of: member.id, admitted: true))
        }
        return roster
    }

    private func request(
        _ joiner: Identity, from inviter: Identity, into roster: inout RoomRoster, hash: UInt8
    ) throws {
        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)
        roster.apply(
            rendered(inviter.id, .joinRequest, hash: hash),
            body: try Payload.joinRequest(attestation))
        roster.apply(
            rendered(inviter.id, .joinConfirmed, hash: hash &+ 100),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: attestation, by: joiner)))
    }

    private func decide(
        _ joiner: Identity, by member: Identity, admitted: Bool, into roster: inout RoomRoster,
        hash: UInt8
    ) throws {
        roster.apply(
            rendered(member.id, .admission, hash: hash),
            body: try Payload.admission(of: joiner.id, admitted: admitted))
    }

    // MARK: The inviter is not one of the approvers

    @Test("Any member: the person who invited them cannot be the one who agrees")
    func anyMemberExcludesTheInviter() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob])
        roster.set(access: .anyMember, by: alice.id)
        try request(joiner, from: alice, into: &roster, hash: 2)

        try decide(joiner, by: alice, admitted: true, into: &roster, hash: 3)
        #expect(!roster.members.contains(joiner.id), "the inviter agreed to their own invitation")

        try decide(joiner, by: bob, admitted: true, into: &roster, hash: 4)
        #expect(roster.members.contains(joiner.id))
    }

    @Test("Any member: with nobody else to ask, the inviter is the one who agrees")
    func anyMemberFallsBackToTheInviter() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice)
        roster.set(access: .anyMember, by: alice.id)
        try request(joiner, from: alice, into: &roster, hash: 2)

        try decide(joiner, by: alice, admitted: true, into: &roster, hash: 3)
        #expect(
            roster.members.contains(joiner.id),
            "a room of one could never let anybody in")
    }

    @Test("Unanimous: everybody but the person who invited them has to agree")
    func unanimousExcludesTheInviter() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let carol = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob, carol])
        roster.set(access: .unanimous, by: alice.id)
        try request(joiner, from: alice, into: &roster, hash: 2)

        try decide(joiner, by: bob, admitted: true, into: &roster, hash: 3)
        #expect(!roster.members.contains(joiner.id), "one of the two was treated as everybody")

        try decide(joiner, by: carol, admitted: true, into: &roster, hash: 4)
        #expect(
            roster.members.contains(joiner.id),
            "everybody who could agree did, and it still asked the inviter")
    }

    @Test("Unanimous: one refusal still keeps somebody out")
    func unanimousStillCountsARefusal() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let carol = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob, carol])
        roster.set(access: .unanimous, by: alice.id)
        try request(joiner, from: alice, into: &roster, hash: 2)

        try decide(joiner, by: bob, admitted: true, into: &roster, hash: 3)
        try decide(joiner, by: carol, admitted: false, into: &roster, hash: 4)
        #expect(!roster.members.contains(joiner.id))
    }

    @Test("A room of two: the inviter agrees, because there is nobody else")
    func unanimousFallsBackToTheInviter() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice)
        roster.set(access: .unanimous, by: alice.id)
        try request(joiner, from: alice, into: &roster, hash: 2)

        try decide(joiner, by: alice, admitted: true, into: &roster, hash: 3)
        #expect(roster.members.contains(joiner.id))
    }

    @Test("The inviter is not asked, and everybody else is")
    func theInviterIsNotAsked() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob])
        roster.set(access: .anyMember, by: alice.id)
        try request(joiner, from: alice, into: &roster, hash: 2)

        #expect(roster.pending(for: alice.id, at: start).isEmpty)
        #expect(roster.pending(for: bob.id, at: start).count == 1)
    }

    // MARK: Named approvers

    @Test("Named members: any one of them is enough, and nobody else will do")
    func namedApproversAreAList() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let carol = Identity.generate()
        let dave = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob, carol, dave])
        roster.set(access: .members([bob.id, carol.id]), by: alice.id)
        try request(joiner, from: alice, into: &roster, hash: 2)

        try decide(joiner, by: dave, admitted: true, into: &roster, hash: 3)
        #expect(!roster.members.contains(joiner.id), "somebody not named let them in")

        try decide(joiner, by: carol, admitted: true, into: &roster, hash: 4)
        #expect(roster.members.contains(joiner.id))
    }

    @Test("A named member who invited them may still agree, because they were named")
    func namedApproversMayInvite() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob])
        roster.set(access: .members([alice.id, bob.id]), by: alice.id)
        try request(joiner, from: alice, into: &roster, hash: 2)

        try decide(joiner, by: alice, admitted: true, into: &roster, hash: 3)
        #expect(roster.members.contains(joiner.id))
    }

    @Test("One name is still a list")
    func oneNameIsAList() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        #expect(RoomAccess.member(bob.id) == .members([bob.id]))
        #expect(RoomAccess.members([bob.id]).namedApprovers == [bob.id])
        #expect(RoomAccess.members([alice.id, bob.id]).namedApprovers.count == 2)
    }

    // MARK: What an older build wrote

    @Test("A room that named one approver before today still names them")
    func theOldSingleNameStillDecodes() throws {
        let who = ParticipantID(rawValue: WideID.of([3]))
        let encoded = String(data: try JSONEncoder().encode(who), encoding: .utf8)!
        let old = Data("{\"member\":{\"_0\":\(encoded)}}".utf8)

        let decoded = try JSONDecoder().decode(RoomAccess.self, from: old)
        #expect(decoded == .members([who]))
    }

    @Test("Every rule survives being written down and read back")
    func everyRuleRoundTrips() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let rules: [RoomAccess] = [
            .open, .founder, .anyMember, .unanimous, .atLeast(3),
            .members([alice.id, bob.id]),
        ]
        for rule in rules {
            let back = try JSONDecoder().decode(
                RoomAccess.self, from: try JSONEncoder().encode(rule))
            #expect(back == rule, "\(rule) did not survive")
        }
    }
}
