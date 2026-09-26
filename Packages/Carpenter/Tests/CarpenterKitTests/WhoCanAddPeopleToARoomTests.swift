import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("Who can add people to a room")
struct WhoCanAddPeopleToARoomTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let room = RoomID()

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

        mutating func invite(_ joiner: Identity, by inviter: Identity) throws -> MembershipAttestation {
            let invite = try TestInvite.issue(
                joining: roster.room, joinerKeys: joiner.publicKeys, by: inviter, at: start)
            write(inviter, .joinRequest, try Payload.joinRequest(invite))
            write(
                inviter, .joinConfirmed,
                try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: joiner)))
            return invite
        }

        mutating func vote(_ voter: Identity, on invite: MembershipAttestation, admit: Bool) throws {
            write(
                voter, .admission,
                try Payload.admission(of: invite.joiner, admitted: admit, invitation: invite.signature))
        }
    }

    private func founded(by founder: Identity, access: RoomAccess) throws -> Room {
        var room = Room(roster: RoomRoster(room: self.room), start: start)
        room.write(founder, .roomProfile, try Payload.roomProfile(name: "Hangar 7"))
        room.roster.set(access: access, by: founder.id)
        return room
    }

    @Test("A removed member cannot bring anybody into an open room")
    func aRemovedMemberCannotInvite() throws {
        let (founder, removed, puppet) = (Identity.generate(), Identity.generate(), Identity.generate())
        var room = try founded(by: founder, access: .open)
        _ = try room.invite(removed, by: founder)
        #expect(room.roster.members.contains(removed.id), "precondition: they were in")
        room.write(founder, .removal, try Payload.removal(of: removed.id))

        _ = try room.invite(puppet, by: removed)

        #expect(
            !room.roster.members.contains(puppet.id),
            """
            Somebody removed from the room invited a second identity of their own and it was admitted. \
            A removed member keeps the old room key, so what they write still opens for everyone.
            """)
    }

    @Test("An invitation is only an invitation when the member who issued it writes it")
    func aRequestIsWrittenByItsInviter() throws {
        let (founder, member, removed, joiner) = (
            Identity.generate(), Identity.generate(), Identity.generate(), Identity.generate()
        )
        var room = try founded(by: founder, access: .open)
        _ = try room.invite(member, by: founder)
        _ = try room.invite(removed, by: founder)
        room.write(founder, .removal, try Payload.removal(of: removed.id))

        let invite = try TestInvite.issue(
            joining: self.room, joinerKeys: joiner.publicKeys, by: removed, at: start)
        room.write(member, .joinRequest, try Payload.joinRequest(invite))
        room.write(
            member, .joinConfirmed,
            try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: joiner)))

        #expect(!room.roster.members.contains(joiner.id))
        #expect(room.roster.requests[joiner.id] == nil)
    }

    @Test("A removed member cannot finish an invitation they sent while they were in the room")
    func aRemovedInviterCannotConfirm() throws {
        let (founder, removed, puppet) = (Identity.generate(), Identity.generate(), Identity.generate())
        var room = try founded(by: founder, access: .open)
        _ = try room.invite(removed, by: founder)
        let invite = try TestInvite.issue(
            joining: self.room, joinerKeys: puppet.publicKeys, by: removed, at: start)
        room.write(removed, .joinRequest, try Payload.joinRequest(invite))
        room.write(founder, .removal, try Payload.removal(of: removed.id))

        room.write(
            removed, .joinConfirmed,
            try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: puppet)))

        #expect(
            !room.roster.members.contains(puppet.id),
            "somebody removed from the room posted the confirmation for their own invitation, and it counted")
    }

    @Test("A vote from outside the room does not admit anybody")
    func aStrangersVoteDoesNotCount() throws {
        let (founder, stranger, joiner) = (Identity.generate(), Identity.generate(), Identity.generate())
        var room = try founded(by: founder, access: .anyMember)
        let invite = try room.invite(joiner, by: founder)
        #expect(!room.roster.members.contains(joiner.id), "precondition: nobody has answered")

        try room.vote(stranger, on: invite, admit: true)

        #expect(!room.roster.members.contains(joiner.id), "a vote from outside the room was counted")
    }

    @Test("A threshold counts the members who agree, and nobody else")
    func aThresholdCountsMembers() throws {
        let (founder, member, stranger, joiner) = (
            Identity.generate(), Identity.generate(), Identity.generate(), Identity.generate()
        )
        var room = try founded(by: founder, access: .atLeast(2))
        _ = try room.invite(member, by: founder)
        try room.vote(founder, on: try #require(room.roster.requests[member.id]), admit: true)
        #expect(room.roster.members.contains(member.id), "precondition: the room has two members")
        let invite = try room.invite(joiner, by: founder)

        try room.vote(founder, on: invite, admit: true)
        try room.vote(stranger, on: invite, admit: true)
        #expect(!room.roster.members.contains(joiner.id), "a stranger made up the numbers")

        try room.vote(member, on: invite, admit: true)
        #expect(room.roster.members.contains(joiner.id))
    }

    @Test("A member who refused and was then removed no longer blocks a unanimous room")
    func aRemovedRefusalLapses() throws {
        let (founder, member, removed, joiner) = (
            Identity.generate(), Identity.generate(), Identity.generate(), Identity.generate()
        )
        var room = try founded(by: founder, access: .unanimous)
        _ = try room.invite(member, by: founder)
        try room.vote(founder, on: try #require(room.roster.requests[member.id]), admit: true)
        _ = try room.invite(removed, by: founder)
        for voter in [founder, member] {
            try room.vote(voter, on: try #require(room.roster.requests[removed.id]), admit: true)
        }
        #expect(room.roster.members == [founder.id, member.id, removed.id], "precondition: three members")

        let invite = try room.invite(joiner, by: founder)
        try room.vote(removed, on: invite, admit: false)
        room.write(founder, .removal, try Payload.removal(of: removed.id))
        try room.vote(founder, on: invite, admit: true)
        try room.vote(member, on: invite, admit: true)

        #expect(
            room.roster.members.contains(joiner.id),
            "every member agreed, and a refusal from somebody no longer in the room still blocked the join")
    }
}
