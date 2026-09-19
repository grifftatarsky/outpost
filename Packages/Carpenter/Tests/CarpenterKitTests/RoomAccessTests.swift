import Foundation
import Testing
import CarpenterKitTesting

@testable import CarpenterKit

@Suite("Room access control")
struct RoomAccessTests {
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

    // MARK: The default

    @Test("A new room is open, because that is what the owner ruled")
    func defaultIsOpen() throws {
        let alice = Identity.generate()
        let roster = try founded(by: alice)
        #expect(roster.access == .open)
    }

    @Test("Open: a valid invitation admits you with nobody's approval")
    func openAdmitsOnInvitation() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice)
        try request(joiner, from: alice, into: &roster, hash: 2)

        #expect(roster.members.contains(joiner.id), "an open room turned an invitation away")
    }

    @Test("Open: nobody is asked to decide")
    func openAsksNobody() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice)
        try request(joiner, from: alice, into: &roster, hash: 2)

        #expect(roster.pending(for: alice.id, at: start).isEmpty)
    }

    // MARK: Founder

    @Test("Founder: only the founder's decision admits, and only the founder is asked")
    func founderDecides() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob])
        roster.set(access: .founder, by: alice.id)
        try request(joiner, from: bob, into: &roster, hash: 2)

        #expect(!roster.members.contains(joiner.id), "admitted before the founder answered")
        #expect(roster.pending(for: bob.id, at: start).isEmpty, "asked somebody whose answer does not count")
        #expect(roster.pending(for: alice.id, at: start).count == 1)

        try decide(joiner, by: bob, admitted: true, into: &roster, hash: 3)
        #expect(!roster.members.contains(joiner.id), "a non-founder's yes admitted them")

        try decide(joiner, by: alice, admitted: true, into: &roster, hash: 4)
        #expect(roster.members.contains(joiner.id))
    }

    // MARK: A named member

    @Test("A named member decides, and nobody else is asked")
    func namedMemberDecides() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob])
        roster.set(access: .member(bob.id), by: alice.id)
        try request(joiner, from: alice, into: &roster, hash: 2)

        #expect(roster.pending(for: alice.id, at: start).isEmpty)
        #expect(roster.pending(for: bob.id, at: start).count == 1)

        try decide(joiner, by: alice, admitted: true, into: &roster, hash: 3)
        #expect(!roster.members.contains(joiner.id), "the wrong member's yes admitted them")

        try decide(joiner, by: bob, admitted: true, into: &roster, hash: 4)
        #expect(roster.members.contains(joiner.id))
    }

    // MARK: Any member

    @Test("Any member: one yes is enough")
    func anyMemberIsEnough() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob])
        roster.set(access: .anyMember, by: alice.id)
        try request(joiner, from: alice, into: &roster, hash: 2)

        #expect(!roster.members.contains(joiner.id))
        try decide(joiner, by: bob, admitted: true, into: &roster, hash: 3)
        #expect(roster.members.contains(joiner.id))
    }

    // MARK: A minimum count

    @Test("A minimum count needs that many, not one fewer")
    func minimumCount() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let carol = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob, carol])
        roster.set(access: .atLeast(2), by: alice.id)
        try request(joiner, from: alice, into: &roster, hash: 2)

        try decide(joiner, by: alice, admitted: true, into: &roster, hash: 3)
        #expect(
            !roster.members.contains(joiner.id),
            "alice invited them, so her own agreement is not one of the two")

        try decide(joiner, by: bob, admitted: true, into: &roster, hash: 4)
        #expect(!roster.members.contains(joiner.id), "one admission satisfied a minimum of two")

        try decide(joiner, by: carol, admitted: true, into: &roster, hash: 5)
        #expect(roster.members.contains(joiner.id))
    }

    // MARK: Unanimous

    @Test("Unanimous: every established member has to have said yes")
    func unanimousNeedsEveryone() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let carol = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob, carol])
        roster.set(access: .unanimous, by: alice.id)
        try request(joiner, from: alice, into: &roster, hash: 2)

        try decide(joiner, by: alice, admitted: true, into: &roster, hash: 3)
        try decide(joiner, by: bob, admitted: true, into: &roster, hash: 4)
        #expect(!roster.members.contains(joiner.id), "admitted while carol had not answered")

        try decide(joiner, by: carol, admitted: true, into: &roster, hash: 5)
        #expect(roster.members.contains(joiner.id))
    }

    @Test("Unanimous: one refusal keeps them out however many others agreed")
    func unanimousRefusal() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob])
        roster.set(access: .unanimous, by: alice.id)
        try request(joiner, from: alice, into: &roster, hash: 2)

        try decide(joiner, by: alice, admitted: true, into: &roster, hash: 3)
        try decide(joiner, by: bob, admitted: false, into: &roster, hash: 4)

        #expect(!roster.members.contains(joiner.id))
    }

    // MARK: Who may change it

    @Test("Only the founder may change how a room admits people")
    func onlyFounderSetsAccess() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob])
        roster.set(access: .unanimous, by: alice.id)

        roster.set(access: .open, by: bob.id)
        #expect(roster.access == .unanimous, "a member other than the founder loosened the room")

        roster.set(access: .open, by: alice.id)
        #expect(roster.access == .open)
    }

    @Test("The setting travels in the log and folds like anything else")
    func accessFoldsFromTheLog() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()

        var roster = try founded(by: alice, alongside: [bob])

        roster.apply(
            rendered(bob.id, .roomAccess, hash: 8), body: try Payload.roomAccess(.unanimous))
        #expect(roster.access == .open, "a non-founder's entry changed the room")

        roster.apply(
            rendered(alice.id, .roomAccess, hash: 9), body: try Payload.roomAccess(.unanimous))
        #expect(roster.access == .unanimous)
    }

    @Test("Tightening a room does not evict the people already in it")
    func tighteningKeepsExistingMembers() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        var roster = try founded(by: alice)
        try request(joiner, from: alice, into: &roster, hash: 2)
        #expect(roster.members.contains(joiner.id))

        roster.set(access: .unanimous, by: alice.id)
        #expect(roster.members.contains(joiner.id), "tightening the room evicted a member")
    }
}
