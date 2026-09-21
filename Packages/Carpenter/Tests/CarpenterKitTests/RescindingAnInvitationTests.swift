@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Taking an invitation back")
struct RescindingAnInvitationTests {
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

    private func invite(
        _ joiner: Identity, by inviter: Identity, to roster: inout RoomRoster, hash: UInt8
    ) throws -> MembershipAttestation {
        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)
        roster.apply(
            rendered(inviter.id, .joinRequest, hash: hash),
            body: try Payload.joinRequest(attestation))
        return attestation
    }

    private func confirm(
        _ attestation: MembershipAttestation, by joiner: Identity, relayedBy relay: Identity,
        to roster: inout RoomRoster, hash: UInt8
    ) throws {
        roster.apply(
            rendered(relay.id, .joinConfirmed, hash: hash),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: attestation, by: joiner)))
    }

    @Test("It is classified, exactly once, as plumbing")
    func classified() {
        #expect(PayloadType.allKnown.contains(.invitationRescinded))
        #expect(PayloadType.plumbing.contains(.invitationRescinded))
        #expect(PayloadType.invitationRescinded.rawValue == 22)
        #expect(RoomRoster.rosterShaping.contains(.invitationRescinded))
    }

    @Test("A rescinded invitation admits nobody, even confirmed")
    func rescindingStopsTheJoin() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let attestation = try invite(joiner, by: inviter, to: &roster, hash: 2)
        roster.apply(
            rendered(inviter.id, .invitationRescinded, hash: 3, at: 10),
            body: try Payload.invitationRescinded(of: attestation))

        try confirm(attestation, by: joiner, relayedBy: inviter, to: &roster, hash: 4)

        #expect(!roster.members.contains(joiner.id), "a rescinded invitation still let somebody in")
        #expect(!roster.confirmed.contains(joiner.id), "it was drawn as waiting on the room")
        #expect(roster.wasRescinded(joiner.id))
    }

    @Test("Rescinding after the confirmation but before the room decides still stops it")
    func rescindingAfterConfirmation() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter, access: .founder)

        let attestation = try invite(joiner, by: inviter, to: &roster, hash: 2)
        try confirm(attestation, by: joiner, relayedBy: inviter, to: &roster, hash: 3)
        #expect(roster.confirmed.contains(joiner.id), "precondition: they were waiting")

        roster.apply(
            rendered(inviter.id, .invitationRescinded, hash: 4, at: 10),
            body: try Payload.invitationRescinded(of: attestation))
        roster.apply(
            rendered(inviter.id, .admission, hash: 5, at: 20),
            body: try Payload.admission(of: joiner.id, admitted: true))

        #expect(!roster.members.contains(joiner.id), "an admission overrode a rescind")
    }

    @Test("Rescinding does not put out somebody already in")
    func rescindingEvictsNobody() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let attestation = try invite(joiner, by: inviter, to: &roster, hash: 2)
        try confirm(attestation, by: joiner, relayedBy: inviter, to: &roster, hash: 3)
        #expect(roster.members.contains(joiner.id), "precondition: they got in")

        roster.apply(
            rendered(inviter.id, .invitationRescinded, hash: 4, at: 10),
            body: try Payload.invitationRescinded(of: attestation))

        #expect(roster.members.contains(joiner.id), "a rescind removed somebody from a room")
        #expect(roster.removal(of: joiner.id) == nil, "it was drawn as a removal, which it is not")
    }

    @Test("Any member may take an invitation back")
    func anyMemberMayWithdraw() throws {
        let inviter = Identity.generate()
        let other = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let theirs = try invite(other, by: inviter, to: &roster, hash: 2)
        try confirm(theirs, by: other, relayedBy: inviter, to: &roster, hash: 3)
        #expect(roster.members.contains(other.id), "precondition: the second member is in")

        let attestation = try invite(joiner, by: inviter, to: &roster, hash: 4)
        roster.apply(
            rendered(other.id, .invitationRescinded, hash: 5, at: 10),
            body: try Payload.invitationRescinded(of: attestation))
        try confirm(attestation, by: joiner, relayedBy: inviter, to: &roster, hash: 6)

        #expect(
            !roster.members.contains(joiner.id),
            "a member's withdrawal did not stop a join")
        #expect(roster.wasRescinded(joiner.id))
    }

    @Test("A stranger's withdrawal is not folded")
    func aStrangerCannotWithdraw() throws {
        let inviter = Identity.generate()
        let stranger = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let attestation = try invite(joiner, by: inviter, to: &roster, hash: 2)
        roster.apply(
            rendered(stranger.id, .invitationRescinded, hash: 3, at: 10),
            body: try Payload.invitationRescinded(of: attestation))
        try confirm(attestation, by: joiner, relayedBy: inviter, to: &roster, hash: 4)

        #expect(
            roster.members.contains(joiner.id),
            "somebody with no part in the room cancelled an invitation")
    }

    @Test("Somebody put out of the room cannot withdraw its invitations")
    func aRemovedMemberCannotWithdraw() throws {
        let inviter = Identity.generate()
        let other = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let theirs = try invite(other, by: inviter, to: &roster, hash: 2)
        try confirm(theirs, by: other, relayedBy: inviter, to: &roster, hash: 3)
        let attestation = try invite(joiner, by: inviter, to: &roster, hash: 4)

        roster.apply(
            rendered(inviter.id, .removal, hash: 5, at: 5),
            body: try Payload.removal(of: other.id))
        roster.apply(
            rendered(other.id, .invitationRescinded, hash: 6, at: 10),
            body: try Payload.invitationRescinded(of: attestation))
        try confirm(attestation, by: joiner, relayedBy: inviter, to: &roster, hash: 7)

        #expect(
            roster.members.contains(joiner.id),
            "somebody who had been put out of the room still cancelled its invitations")
    }

    @Test("The founder may take back somebody else's invitation in their own room")
    func theFounderMayWithdraw() throws {
        let founder = Identity.generate()
        let other = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: founder)

        let theirs = try invite(other, by: founder, to: &roster, hash: 2)
        try confirm(theirs, by: other, relayedBy: founder, to: &roster, hash: 3)
        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: other, at: start)
        roster.apply(
            rendered(other.id, .joinRequest, hash: 4),
            body: try Payload.joinRequest(attestation))
        roster.apply(
            rendered(founder.id, .invitationRescinded, hash: 5, at: 10),
            body: try Payload.invitationRescinded(of: attestation))
        try confirm(attestation, by: joiner, relayedBy: other, to: &roster, hash: 6)

        #expect(!roster.members.contains(joiner.id))
        #expect(roster.wasRescinded(joiner.id))
    }

    @Test("Taking back somebody else's invitation still evicts nobody")
    func aThirdPartyWithdrawalEvictsNobody() throws {
        let inviter = Identity.generate()
        let other = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let theirs = try invite(other, by: inviter, to: &roster, hash: 2)
        try confirm(theirs, by: other, relayedBy: inviter, to: &roster, hash: 3)
        let attestation = try invite(joiner, by: inviter, to: &roster, hash: 4)
        try confirm(attestation, by: joiner, relayedBy: inviter, to: &roster, hash: 5)
        #expect(roster.members.contains(joiner.id), "precondition: the joiner is in")

        roster.apply(
            rendered(other.id, .invitationRescinded, hash: 6, at: 20),
            body: try Payload.invitationRescinded(of: attestation))

        #expect(
            roster.members.contains(joiner.id),
            "a withdrawal put somebody out of a room they were already in")
    }

    @Test("A fresh invitation is not rescinded by the old one's withdrawal")
    func aFreshInvitationIsUnaffected() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let first = try invite(joiner, by: inviter, to: &roster, hash: 2)
        roster.apply(
            rendered(inviter.id, .invitationRescinded, hash: 3, at: 10),
            body: try Payload.invitationRescinded(of: first))

        let second = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start.addingTimeInterval(20))
        roster.apply(
            rendered(inviter.id, .joinRequest, hash: 4, at: 20),
            body: try Payload.joinRequest(second))
        try confirm(second, by: joiner, relayedBy: inviter, to: &roster, hash: 5)

        #expect(roster.members.contains(joiner.id), "a new invitation was refused by an old rescind")
        #expect(!roster.wasRescinded(joiner.id))
    }

    @Test("A rescinded invitation stops being outstanding")
    func itLeavesTheList() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: inviter)

        let attestation = try invite(joiner, by: inviter, to: &roster, hash: 2)
        #expect(roster.pendingInvitations(at: start).count == 1)
        #expect(roster.invited.contains(joiner.id))

        roster.apply(
            rendered(inviter.id, .invitationRescinded, hash: 3, at: 10),
            body: try Payload.invitationRescinded(of: attestation))

        #expect(roster.pendingInvitations(at: start).isEmpty)
        #expect(!roster.invited.contains(joiner.id))
    }

    @Test("A withdrawn invitation is not still waiting for an answer")
    func withdrawnIsNotPending() throws {
        let founder = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: founder, access: .founder)

        let attestation = try invite(joiner, by: founder, to: &roster, hash: 2)
        try confirm(attestation, by: joiner, relayedBy: founder, to: &roster, hash: 3)
        #expect(
            roster.pending(for: founder.id, at: start).count == 1,
            "precondition: the room is waiting on an answer")

        roster.apply(
            rendered(founder.id, .invitationRescinded, hash: 4, at: 10),
            body: try Payload.invitationRescinded(of: attestation))

        #expect(
            roster.pending(for: founder.id, at: start).isEmpty,
            "the room kept offering a decision it had already made")
        #expect(
            throws: MembershipError.invitationWithdrawn,
            "an admission could still be written for a withdrawn invitation"
        ) {
            try roster.verify(attestation, inviterKeys: founder.publicKeys, at: start)
        }
    }

    @Test("An offer that ran out with nothing back is not waiting for an answer either")
    func lapsedIsNotPending() throws {
        let founder = Identity.generate()
        let ignored = Identity.generate()
        let answered = Identity.generate()
        var roster = try founded(by: founder, access: .founder)

        _ = try invite(ignored, by: founder, to: &roster, hash: 2)
        let taken = try invite(answered, by: founder, to: &roster, hash: 3)
        try confirm(taken, by: answered, relayedBy: founder, to: &roster, hash: 4)

        let afterwards = start.addingTimeInterval(2 * 24 * 60 * 60)
        let waiting = roster.pending(for: founder.id, at: afterwards).map(\.joiner)

        #expect(
            !waiting.contains(ignored.id),
            "the room offered a decision on an invitation that had run out with nothing back")
        #expect(
            waiting.contains(answered.id),
            "somebody who answered in time was dropped because the room was slow")
    }

    @Test("It carries fallback text, because an older build will draw it")
    func carriesFallbackText() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)

        let fallback = try #require(try Payload.invitationRescinded(of: attestation).fallbackText)
        #expect(!fallback.isEmpty)
    }
}

@MainActor
@Suite("Taking an invitation back, through the session", .serialized)
struct SessionRescindTests {
    private func pair() async throws -> (
        alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        return (alice, bob, mailbox)
    }

    private func settle(
        _ everyone: [AppSession], _ mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox) }
        }
    }

    @Test("Somebody holding a withdrawn invitation cannot join on it")
    func aWithdrawnInvitationCannotBeUsed() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")
        let bobID = try #require(bob.enrolment?.identity.id)

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await alice.rescind(invite.attestation)
        #expect(alice.pendingInvitations(in: room).isEmpty, "the purged invitation is still listed")

        try await bob.redeem(inviteCode: try invite.encoded())
        try await settle([alice, bob], mailbox)

        #expect(!alice.roster(of: room).members.contains(bobID), "a withdrawn invitation let him in")
        #expect(bob.rooms.isEmpty, "the joiner was handed a room from a withdrawn invitation")
    }

    @Test("Rescinding after somebody is in is refused, and changes nothing")
    func tooLateToWithdraw() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")
        let bobID = try #require(bob.enrolment?.identity.id)

        try await join(bob, into: room, of: alice, through: mailbox)
        let theirs = try #require(alice.roster(of: room).requests[bobID])

        await #expect(throws: MembershipError.alreadyInTheRoom) { try await alice.rescind(theirs) }
        try await settle([alice, bob], mailbox)

        #expect(alice.roster(of: room).members.contains(bobID))
        #expect(bob.roster(of: room).members.contains(bobID), "his own copy lost him the room")
    }

    @Test("A room-mate may withdraw an invitation somebody else made, and an outsider may not")
    func standingIsWhatDecides() async throws {
        let (alice, bob, mailbox) = try await pair()
        let carol = TestSession.make()
        let dave = TestSession.make()
        await carol.load()
        await dave.load()
        try await carol.createIdentity(displayName: "Carol")
        try await dave.createIdentity(displayName: "Dave")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: room, of: alice, through: mailbox)

        let invite = try await alice.invite(
            joinerCode: carol.identityCode(), joining: room, mailbox: nil)
        try await settle([alice, bob], mailbox)

        await #expect(throws: MembershipError.notAMember) {
            try await dave.rescind(invite.attestation)
        }

        let carolID = try #require(carol.enrolment?.identity.id)
        try await bob.rescind(invite.attestation)
        try await settle([alice, bob], mailbox)
        for session in [alice, bob] {
            #expect(
                session.roster(of: room).wasRescinded(carolID),
                "a member's withdrawal of somebody else's offer was not folded")
        }
    }

    @Test("An invitation from a member who has left can be taken back by anybody still here")
    func anOrphanedInvitationCanBeCleared() async throws {
        let (alice, bob, mailbox) = try await pair()
        let carol = TestSession.make()
        await carol.load()
        try await carol.createIdentity(displayName: "Carol")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: room, of: alice, through: mailbox)

        let invite = try await alice.invite(
            joinerCode: carol.identityCode(), joining: room, mailbox: nil, lasting: .indefinite)
        try await settle([alice, bob], mailbox)
        try await alice.leave(room)
        try await settle([alice, bob], mailbox, rounds: 8)

        let carolID = try #require(carol.enrolment?.identity.id)
        #expect(
            bob.pendingInvitations(in: room).contains { $0.joiner == carolID },
            "precondition: the offer outlived the member who made it")

        try await bob.rescind(invite.attestation)
        try await settle([alice, bob], mailbox)
        #expect(
            bob.pendingInvitations(in: room).isEmpty,
            "nobody left in the room could clear an offer from somebody who had gone")
    }

    @Test("Inviting again after withdrawing works")
    func aFreshInvitationAfterwards() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")
        let bobID = try #require(bob.enrolment?.identity.id)

        let first = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await alice.rescind(first.attestation)

        try await join(bob, into: room, of: alice, through: mailbox)

        #expect(alice.roster(of: room).members.contains(bobID))
        #expect(bob.rooms.contains { $0.id == room })
    }
}
