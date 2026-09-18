@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Confirming that the right person joined")
struct ConfirmingAJoinTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let room = RoomID()

    private func rendered(
        _ author: ParticipantID, _ type: PayloadType, hash: UInt8
    ) -> RenderedEntry {
        RenderedEntry(
            id: EntryHash(rawValue: Data(repeating: hash, count: 32)), type: type, author: author,
            device: DeviceID(rawValue: WideID.of([])), wallTime: start, room: room, content: .text(""),
            editedAt: nil, replyingTo: nil, reactions: [:])
    }

    private func room(
        access: RoomAccess, founder: Identity, inviter: Identity? = nil, joiner: Identity
    ) throws -> RoomRoster {
        var roster = RoomRoster(room: room)
        roster.apply(
            rendered(founder.id, .roomProfile, hash: 1),
            body: try Payload.roomProfile(name: "Hangar 7"))
        roster.set(access: access, by: founder.id)

        let issuer = inviter ?? founder
        let invite = try TestInvite.issue(
            joining: self.room, joinerKeys: joiner.publicKeys, by: issuer, at: start)
        roster.apply(
            rendered(issuer.id, .joinRequest, hash: 2), body: try Payload.joinRequest(invite))
        roster.apply(
            rendered(issuer.id, .joinConfirmed, hash: 3),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: invite, by: joiner)))
        return roster
    }

    @Test("The phrase can still be confirmed after the invitation has lapsed")
    func confirmingSurvivesExpiry() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()
        let roster = try room(access: .open, founder: alice, joiner: joiner)
        let invite = try #require(roster.awaitingConfirmation(by: alice.id).first)
        let afterwards = invite.expiresAt.addingTimeInterval(60 * 60 * 24)

        #expect(throws: MembershipError.expired) {
            try roster.verify(invite, inviterKeys: alice.publicKeys, at: afterwards)
        }
        #expect(throws: Never.self) {
            try roster.verify(
                invite, inviterKeys: alice.publicKeys, at: afterwards, allowingExpired: true)
        }
    }

    @Test("Letting an expiry pass does not let anything else pass")
    func expiryIsTheOnlyThingSetAside() throws {
        let alice = Identity.generate()
        let mallory = Identity.generate()
        let joiner = Identity.generate()
        let roster = try room(access: .open, founder: alice, joiner: joiner)
        let invite = try #require(roster.awaitingConfirmation(by: alice.id).first)
        let afterwards = invite.expiresAt.addingTimeInterval(60 * 60 * 24)

        #expect(throws: MembershipError.wrongInviter) {
            try roster.verify(
                invite, inviterKeys: mallory.publicKeys, at: afterwards, allowingExpired: true)
        }
    }

    @Test("An open room asks the inviter to check the phrase")
    func openRoomAsksTheInviter() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        let roster = try room(access: .open, founder: alice, joiner: joiner)

        #expect(roster.members.contains(joiner.id), "an open room did not admit on the invitation")
        #expect(roster.pending(for: alice.id, at: start).isEmpty, "an open room asked for an approval")
        #expect(
            roster.awaitingConfirmation(by: alice.id).map(\.joiner) == [joiner.id],
            "nobody was asked whether the right person turned up")
    }

    @Test("Only the person who invited them is asked")
    func onlyTheInviter() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let joiner = Identity.generate()

        var roster = try room(access: .open, founder: alice, joiner: bob)
        let invite = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: bob, at: start)
        roster.apply(
            rendered(bob.id, .joinRequest, hash: 9), body: try Payload.joinRequest(invite))
        roster.apply(
            rendered(bob.id, .joinConfirmed, hash: 10),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: invite, by: joiner)))

        #expect(roster.awaitingConfirmation(by: bob.id).map(\.joiner) == [joiner.id])
        #expect(
            !roster.awaitingConfirmation(by: alice.id).map(\.joiner).contains(joiner.id),
            "somebody who read no phrase was asked to confirm it")
    }

    @Test("Once you have answered, it stops asking")
    func answeringClearsIt() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        var roster = try room(access: .open, founder: alice, joiner: joiner)
        #expect(roster.awaitingConfirmation(by: alice.id).count == 1)

        roster.apply(
            rendered(alice.id, .admission, hash: 4),
            body: try Payload.admission(of: joiner.id, admitted: true))

        #expect(roster.awaitingConfirmation(by: alice.id).isEmpty)
    }

    @Test("Refusing after the fact stops the keys and not the membership")
    func refusingCutsTheKeysOnly() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        var roster = try room(access: .open, founder: alice, joiner: joiner)
        #expect(roster.rewrapTargets(of: alice.id).contains(joiner.id))

        roster.apply(
            rendered(alice.id, .admission, hash: 4),
            body: try Payload.admission(of: joiner.id, admitted: false))

        #expect(roster.awaitingConfirmation(by: alice.id).isEmpty, "it went on asking")
        #expect(
            !roster.rewrapTargets(of: alice.id).contains(joiner.id),
            "a refusal did not stop the keys, which is the only thing it can actually do")
        #expect(
            roster.members.contains(joiner.id),
            "a refusal removed somebody from a room, which nothing in this app can do yet")
    }

    @Test("A room that already asks for approval does not ask again")
    func policiesThatAskAreLeftAlone() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        for access in [RoomAccess.founder, .anyMember, .unanimous, .atLeast(2)] {
            let roster = try room(access: access, founder: alice, joiner: joiner)
            #expect(
                roster.awaitingConfirmation(by: alice.id).isEmpty,
                "\(access) asked the inviter a second time")
            #expect(!roster.pending(for: alice.id, at: start).isEmpty, "\(access) asked nobody at all")
        }
    }

    @Test("Somebody who has not joined yet is not waiting to be confirmed")
    func onlyPeopleWhoActuallyJoined() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        var roster = RoomRoster(room: room)
        roster.apply(
            rendered(alice.id, .roomProfile, hash: 1),
            body: try Payload.roomProfile(name: "Hangar 7"))
        roster.set(access: .founder, by: alice.id)
        let invite = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: alice, at: start)
        roster.apply(
            rendered(alice.id, .joinRequest, hash: 2), body: try Payload.joinRequest(invite))

        #expect(!roster.members.contains(joiner.id))
        #expect(roster.awaitingConfirmation(by: alice.id).isEmpty)
        #expect(roster.pendingInvitations(at: start).count == 1, "it stopped being an invitation")
    }
}

@MainActor
@Suite("Confirming a join, through the session", .serialized)
struct SessionConfirmationTests {
    @Test("An open room offers the confirmation, and answering it clears it")
    func confirmingClearsIt() async throws {
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let mailbox = InMemoryMailbox()
        let room = try await alice.createRoom(named: "Hangar 7")
        let bobKeys = try #require(bob.enrolment?.identity.publicKeys)
        try await join(bob, into: room, of: alice, through: mailbox)

        #expect(alice.pendingJoins(in: room).isEmpty)
        let waiting = alice.awaitingConfirmation(in: room)
        #expect(waiting.map(\.joiner) == [bobKeys.participantID])

        let attestation = try #require(waiting.first)
        try await alice.decide(on: attestation, admit: true)

        #expect(
            alice.awaitingConfirmation(in: room).isEmpty,
            "answering the confirmation left it on screen")
        #expect(alice.roster(of: room).members.contains(bobKeys.participantID))
    }

    @Test("Saying it does not match stops the room key going to them")
    func refusingStopsTheKeys() async throws {
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let mailbox = InMemoryMailbox()
        let room = try await alice.createRoom(named: "Hangar 7")
        let bobKeys = try #require(bob.enrolment?.identity.publicKeys)
        try await join(bob, into: room, of: alice, through: mailbox)

        let attestation = try #require(alice.awaitingConfirmation(in: room).first)
        try await alice.decide(on: attestation, admit: false)

        let me = try #require(alice.enrolment?.identity.id)
        #expect(alice.awaitingConfirmation(in: room).isEmpty)
        #expect(!alice.roster(of: room).rewrapTargets(of: me).contains(bobKeys.participantID))
        #expect(
            alice.roster(of: room).members.contains(bobKeys.participantID),
            "saying the phrase did not match removed somebody, which nothing can do yet")
    }
}
