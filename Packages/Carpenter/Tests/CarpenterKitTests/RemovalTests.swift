@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Removing somebody from a room")
struct RemovalTests {
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

    private func room(founder: Identity, joining: [Identity]) throws -> RoomRoster {
        var roster = RoomRoster(room: room)
        roster.apply(
            rendered(founder.id, .roomProfile, hash: 1),
            body: try Payload.roomProfile(name: "Hangar 7"))

        for (index, joiner) in joining.enumerated() {
            let invite = try TestInvite.issue(
                joining: self.room, joinerKeys: joiner.publicKeys, by: founder, at: start)
            roster.apply(
                rendered(founder.id, .joinRequest, hash: UInt8(20 + index)),
                body: try Payload.joinRequest(invite))
            roster.apply(
                rendered(founder.id, .joinConfirmed, hash: UInt8(40 + index)),
                body: try Payload.joinConfirmed(
                    try JoinConfirmedBody.signed(confirming: invite, by: joiner)))
        }
        return roster
    }

    private func remove(
        _ person: Identity, by author: Identity, from roster: inout RoomRoster,
        hash: UInt8 = 90, at offset: TimeInterval = 10
    ) throws {
        roster.apply(
            rendered(author.id, .removal, hash: hash, at: offset),
            body: try Payload.removal(of: person.id))
    }

    // MARK: The act itself

    @Test("A member removed is out of the room")
    func removalTakesEffect() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        var roster = try room(founder: alice, joining: [sam])
        #expect(roster.members.contains(sam.id))

        try remove(sam, by: alice, from: &roster)

        #expect(!roster.members.contains(sam.id), "a removed member was still in the room")
        #expect(roster.removal(of: sam.id)?.by == alice.id, "the room did not record who did it")
    }

    @Test("A removed member is handed no more room keys")
    func removalStopsTheKeys() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        let bo = Identity.generate()
        var roster = try room(founder: alice, joining: [sam, bo])
        #expect(roster.rewrapTargets(of: alice.id).contains(sam.id))

        try remove(sam, by: alice, from: &roster)

        #expect(!roster.rewrapTargets(of: alice.id).contains(sam.id))
        #expect(
            roster.rewrapTargets(of: alice.id).contains(bo.id),
            "removing one person stopped the keys to everybody")
        #expect(
            !roster.rewrapTargets(of: bo.id).contains(sam.id),
            "only the remover stopped rewrapping, so the room disagreed about who is in it")
    }

    @Test("A member can remove the person who made the room")
    func anybodyMayRemoveTheFounder() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        var roster = try room(founder: alice, joining: [sam])

        try remove(alice, by: sam, from: &roster)

        #expect(!roster.members.contains(alice.id), "the founder was treated as unremovable")
        #expect(roster.members.contains(sam.id))
    }

    // MARK: Standing

    @Test("Somebody not in the room cannot remove anyone")
    func strangersCannotRemove() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        let stranger = Identity.generate()
        var roster = try room(founder: alice, joining: [sam])

        try remove(sam, by: stranger, from: &roster)

        #expect(roster.members.contains(sam.id), "a stranger emptied a room they were never in")
        #expect(roster.removal(of: sam.id) == nil)
    }

    @Test("Somebody already removed cannot remove anyone")
    func theRemovedCannotRemove() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        let bo = Identity.generate()
        var roster = try room(founder: alice, joining: [sam, bo])

        try remove(sam, by: alice, from: &roster, hash: 90, at: 10)
        try remove(bo, by: sam, from: &roster, hash: 91, at: 20)

        #expect(roster.members.contains(bo.id), "somebody out of the room removed somebody in it")
    }

    @Test("Nobody removes themselves")
    func selfRemovalIsNotLeaving() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        var roster = try room(founder: alice, joining: [sam])

        try remove(sam, by: sam, from: &roster)

        #expect(roster.members.contains(sam.id))
        #expect(roster.removal(of: sam.id) == nil, "leaving was recorded as having been removed")
    }

    @Test("Removing somebody who is not in the room does nothing")
    func removingANonMember() throws {
        let alice = Identity.generate()
        let stranger = Identity.generate()
        var roster = try room(founder: alice, joining: [])

        try remove(stranger, by: alice, from: &roster)

        #expect(roster.removal(of: stranger.id) == nil, "a removal notice was invented about somebody who was never here")
    }

    // MARK: Two people removing at once

    @Test("If two people remove each other, the first one wins")
    func firstRemoverWins() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        var roster = try room(founder: alice, joining: [sam])

        try remove(sam, by: alice, from: &roster, hash: 90, at: 10)
        try remove(alice, by: sam, from: &roster, hash: 91, at: 11)

        #expect(!roster.members.contains(sam.id))
        #expect(roster.members.contains(alice.id), "the loser of the race removed the winner")
    }

    @Test("Every device folding the same order agrees who is out")
    func theFoldIsDeterministic() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()

        var one = try room(founder: alice, joining: [sam])
        try remove(alice, by: sam, from: &one, hash: 91, at: 11)
        try remove(sam, by: alice, from: &one, hash: 90, at: 10)

        var two = try room(founder: alice, joining: [sam])
        try remove(alice, by: sam, from: &two, hash: 91, at: 11)
        try remove(sam, by: alice, from: &two, hash: 90, at: 10)

        #expect(one.members == two.members)
        #expect(one.members.contains(sam.id), "the second fold gave a different answer")
        #expect(!one.members.contains(alice.id))
    }

    // MARK: Coming back

    @Test("An admission still in flight cannot undo a removal")
    func staleAdmissionCannotRestore() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        var roster = try room(founder: alice, joining: [sam])

        try remove(sam, by: alice, from: &roster, hash: 90, at: 10)
        roster.apply(
            rendered(alice.id, .admission, hash: 92, at: 20),
            body: try Payload.admission(of: sam.id, admitted: true))

        #expect(!roster.members.contains(sam.id), "an admission put a removed member back")
        #expect(roster.removal(of: sam.id) != nil)
    }

    @Test("A new invitation, confirmed, brings them back and clears the removal")
    func aFreshInvitationRestores() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        var roster = try room(founder: alice, joining: [sam])
        try remove(sam, by: alice, from: &roster, hash: 90, at: 10)

        let again = try TestInvite.issue(
            joining: room, joinerKeys: sam.publicKeys, by: alice, at: start.addingTimeInterval(30))
        roster.apply(
            rendered(alice.id, .joinRequest, hash: 93, at: 30),
            body: try Payload.joinRequest(again))
        #expect(
            !roster.members.contains(sam.id),
            "an invitation alone put a removed member back, on a check nobody made")

        roster.apply(
            rendered(alice.id, .joinConfirmed, hash: 95, at: 31),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: again, by: sam)))

        #expect(roster.members.contains(sam.id), "a confirmed invitation did not bring them back")
        #expect(
            roster.removal(of: sam.id) == nil,
            "somebody standing in the room was still told they had been removed")
        #expect(roster.mayWrite(sam.id))
    }

    @Test("Replaying the invitation somebody was removed on lets nobody in")
    func aSpentInvitationCannotBeReplayed() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        var roster = try room(founder: alice, joining: [sam])
        let spent = try #require(roster.requests[sam.id])
        try remove(sam, by: alice, from: &roster, hash: 90, at: 10)

        roster.apply(
            rendered(alice.id, .joinRequest, hash: 96, at: 40),
            body: try Payload.joinRequest(spent))
        roster.apply(
            rendered(alice.id, .joinConfirmed, hash: 97, at: 41),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: spent, by: sam)))

        #expect(
            !roster.members.contains(sam.id),
            "a removal was undone by replaying the invitation it ended")
        #expect(roster.removal(of: sam.id) != nil, "the removal notice was wiped by a replay")
    }

    @Test("An approval does not stand in for the confirmation of a new invitation")
    func anApprovalIsNotAConfirmation() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        var roster = try room(founder: alice, joining: [sam])
        roster.set(access: .founder, by: alice.id)
        try remove(sam, by: alice, from: &roster, hash: 90, at: 10)

        let again = try TestInvite.issue(
            joining: room, joinerKeys: sam.publicKeys, by: alice, at: start.addingTimeInterval(30))
        roster.apply(
            rendered(alice.id, .joinRequest, hash: 93, at: 30),
            body: try Payload.joinRequest(again))
        roster.apply(
            rendered(alice.id, .admission, hash: 94, at: 32),
            body: try Payload.admission(of: sam.id, admitted: true))

        #expect(
            !roster.members.contains(sam.id),
            "the room let somebody in on an approval, having never heard from them")
    }

    @Test("Being removed twice still comes back cleanly")
    func removedTwiceThenReadded() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        var roster = try room(founder: alice, joining: [sam])

        try remove(sam, by: alice, from: &roster, hash: 90, at: 10)
        try remove(sam, by: alice, from: &roster, hash: 94, at: 15)

        let again = try TestInvite.issue(
            joining: room, joinerKeys: sam.publicKeys, by: alice, at: start.addingTimeInterval(30))
        roster.apply(
            rendered(alice.id, .joinRequest, hash: 93, at: 30),
            body: try Payload.joinRequest(again))
        roster.apply(
            rendered(alice.id, .joinConfirmed, hash: 95, at: 31),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: again, by: sam)))

        #expect(roster.members.contains(sam.id))
        #expect(roster.removal(of: sam.id) == nil)
    }

    // MARK: What the removed member's own copy says

    @Test("The removed member's own copy is what tells them")
    func theirOwnCopyTellsThem() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        var roster = try room(founder: alice, joining: [sam])
        #expect(roster.mayWrite(sam.id))

        try remove(sam, by: alice, from: &roster)

        #expect(roster.removal(of: sam.id)?.by == alice.id)
        #expect(!roster.mayWrite(sam.id), "a removed member could still write to the room")
        #expect(roster.mayWrite(alice.id), "everybody else was blocked too")
    }

    @Test("Somebody who was never here is not treated as removed")
    func aStrangerIsNotRemoved() throws {
        let alice = Identity.generate()
        let stranger = Identity.generate()
        let roster = try room(founder: alice, joining: [])

        #expect(roster.removal(of: stranger.id) == nil)
        #expect(roster.mayWrite(stranger.id))
    }

    @Test("Removal takes nothing back")
    func nothingIsTakenBack() throws {
        let alice = Identity.generate()
        let sam = Identity.generate()
        var roster = try room(founder: alice, joining: [sam])
        let before = roster.members

        try remove(sam, by: alice, from: &roster)

        #expect(before.contains(sam.id))
        #expect(roster.removal(of: sam.id)?.at == start.addingTimeInterval(10))
    }
}

@MainActor
@Suite("Removing somebody, through the session", .serialized)
struct SessionRemovalTests {
    private func roomWithTwo() async throws -> (
        alice: AppSession, bob: AppSession, room: ConversationID, bobID: ParticipantID
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let keys = try #require(bob.enrolment?.identity.publicKeys)
        try await join(bob, into: room, of: alice, through: mailbox)
        try #require(alice.roster(of: room).members.contains(keys.participantID))

        return (alice, bob, room, keys.participantID)
    }

    @Test("Removing somebody turns the room's key")
    func removalAdvancesTheEpoch() async throws {
        let (alice, _, room, bob) = try await roomWithTwo()
        let before = try #require(alice.epoch(of: room))

        try await alice.remove(bob, from: room)

        let after = try #require(alice.epoch(of: room))
        #expect(after > before, "a membership change did not change the key")
        #expect(!alice.roster(of: room).members.contains(bob))
        #expect(!alice.roster(of: room).rewrapTargets(of: try #require(alice.enrolment?.identity.id)).contains(bob))
    }

    @Test("A member cannot remove themselves through the session")
    func sessionRefusesSelfRemoval() async throws {
        let (alice, _, room, _) = try await roomWithTwo()
        let me = try #require(alice.enrolment?.identity.id)

        await #expect(throws: MembershipError.cannotRemoveYourself) {
            try await alice.remove(me, from: room)
        }
    }

    @Test("Removing somebody who is not in the room is refused rather than written")
    func sessionRefusesNonMembers() async throws {
        let (alice, _, room, bob) = try await roomWithTwo()
        try await alice.remove(bob, from: room)

        await #expect(throws: MembershipError.notAMember) {
            try await alice.remove(bob, from: room)
        }
    }

    @Test("The removal reaches the person it names, in their own log")
    func itReachesTheRemovedMember() async throws {
        let (alice, bob, room, bobID) = try await roomWithTwo()
        try await alice.remove(bobID, from: room)

        let entries = alice.roster(of: room)
        #expect(entries.removal(of: bobID)?.by == alice.enrolment?.identity.id)
        #expect(bob.removal(from: room) == nil, "Bob has not synced yet and was told anyway")
    }

    @Test("The room says what happened")
    func theRoomSaysWhatHappened() async throws {
        let (alice, _, room, bob) = try await roomWithTwo()
        try await alice.remove(bob, from: room)

        let notices = alice.transcript(in: room).compactMap { entry -> RoomNotice? in
            if case .notice(let notice) = entry { return notice }
            return nil
        }
        let removals = notices.compactMap { notice -> (Member, Member)? in
            if case .removed(let who, let by) = notice.kind { return (who, by) }
            return nil
        }

        #expect(removals.count == 1, "the room drew no removal, or drew it twice")
        #expect(removals.first?.0.id == bob)
        #expect(removals.first?.1.id == alice.enrolment?.identity.id)
    }
}

@MainActor
@Suite("Removal, enforced by the session", .serialized)
struct RemovalEnforcementTests {
    private func roomWithTwo() async throws -> (
        alice: AppSession, room: ConversationID, bob: ParticipantID
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let keys = try #require(bob.enrolment?.identity.publicKeys)
        try await join(bob, into: room, of: alice, through: mailbox)
        try #require(alice.roster(of: room).members.contains(keys.participantID))
        return (alice, room, keys.participantID)
    }

    @Test("A removed member's own device will not write into the room")
    func aRemovedMemberCannotWrite() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        try await bob.send("while I am in", to: room)
        #expect(bob.roster(of: room).mayWrite(try #require(bob.enrolment?.identity.id)))

        try await alice.remove(try #require(bob.enrolment?.identity.id), from: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        let bobID = try #require(bob.enrolment?.identity.id)
        #expect(bob.roster(of: room).removal(of: bobID) != nil, "the removal never reached Bob")

        await #expect(throws: MembershipError.removedFromThisRoom) {
            try await bob.send("after I was removed", to: room)
        }
    }

    @Test("Once the removal has folded, that device's session declines the write")
    func theRemovedDeviceDeclines() async throws {
        let (alice, room, bob) = try await roomWithTwo()
        try await alice.remove(bob, from: room)

        try await alice.send("fine", to: room)

        #expect(!alice.roster(of: room).mayWrite(bob))
        #expect(alice.roster(of: room).mayWrite(try #require(alice.enrolment?.identity.id)))
    }

    @Test("Keys are held only when this device is behind and somebody here has been removed")
    func keysAreHeldOnlyWhenBothAreTrue() {
        #expect(AppSession.withholdsKeys(viewMayBeStale: true, roomHasAbsences: true))
        #expect(!AppSession.withholdsKeys(viewMayBeStale: true, roomHasAbsences: false))
        #expect(!AppSession.withholdsKeys(viewMayBeStale: false, roomHasAbsences: true))
        #expect(!AppSession.withholdsKeys(viewMayBeStale: false, roomHasAbsences: false))
    }

    @Test("Holding keys does not hold the removal")
    func theRemovalItselfIsUnconditional() async throws {
        let (alice, room, bob) = try await roomWithTwo()
        try await alice.remove(bob, from: room)

        #expect(alice.roster(of: room).removals.count == 1)
        #expect(!alice.roster(of: room).members.contains(bob))
    }
}
