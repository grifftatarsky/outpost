@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("An invitation that ran out")
struct AnOfferThatRanOutTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let day: TimeInterval = 24 * 60 * 60
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

    // MARK: What the fold answers, and must go on answering

    @Test("The fold admits on a confirmation whenever one lands, and never asks the date")
    func theFoldNeverAsksTheDate() throws {
        let founder = Identity.generate()
        let joiner = Identity.generate()
        var roster = try founded(by: founder)

        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: founder, at: start, lasting: .aDay)
        roster.apply(
            rendered(founder.id, .joinRequest, hash: 2),
            body: try Payload.joinRequest(attestation))
        roster.apply(
            rendered(founder.id, .joinConfirmed, hash: 3, at: 8 * day),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: attestation, by: joiner)))

        #expect(
            roster.members.contains(joiner.id),
            "the fold started asking whether the invitation had run out")
    }

    @Test("A member is still a member a thousand days after the invitation ran out")
    @MainActor
    func timePassingEvictsNobody() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: start)
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil, lasting: .aDay)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<6 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        let bobID = try #require(bob.enrolment?.identity.id)
        #expect(alice.roster(of: room).members.contains(bobID), "precondition: Bob joined")

        clock.advance(by: 1000 * day)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        for session in [alice, bob] {
            let roster = session.roster(of: room)
            #expect(roster.members.contains(bobID), "a date passing put somebody out of a room")
            #expect(roster.removal(of: bobID) == nil, "an eviction with nobody to name")
            #expect(roster.departure(of: bobID) == nil)
            #expect(roster.absent.isEmpty)
        }
        #expect(bob.roster(of: room).mayWrite(bobID))
    }

    // MARK: The enforcement, which is a write on the inviter's own device

    @Test("An inviter does not relay a confirmation collected after the offer ran out")
    @MainActor
    func aLateConfirmationIsNotRelayed() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: start)
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil, lasting: .aDay)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<3 { try await bob.sync(through: mailbox) }

        clock.advance(by: 2 * day)
        for _ in 0..<6 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        let bobID = try #require(bob.enrolment?.identity.id)
        let roster = alice.roster(of: room)
        #expect(
            !roster.hasConfirmed(bobID),
            "a confirmation collected after the offer ran out was written into the room")
        #expect(!roster.members.contains(bobID))
    }

    @Test("A confirmation collected while the offer still stood is relayed")
    @MainActor
    func anInTimeConfirmationStillLands() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: start)
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil, lasting: .aDay)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<3 { try await bob.sync(through: mailbox) }

        clock.advance(by: day - 1)
        for _ in 0..<6 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        let bobID = try #require(bob.enrolment?.identity.id)
        #expect(
            alice.roster(of: room).members.contains(bobID),
            "an invitation that had not run out was refused")
    }

    // MARK: The seam — after the confirmation, the date stops mattering

    @Test("Somebody who answered in time can be let in after the date, and nobody else can")
    @MainActor
    func theRoomMayStillDecideAfterwards() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: start)
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.setAccess(.founder, in: room)
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil, lasting: .aDay)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<6 {
            try await bob.sync(through: mailbox)
            try await alice.sync(through: mailbox)
        }

        let bobID = try #require(bob.enrolment?.identity.id)
        #expect(alice.roster(of: room).hasConfirmed(bobID), "precondition: Bob answered in time")

        clock.advance(by: 2 * day)
        let waiting = try #require(alice.pendingJoins(in: room).first { $0.joiner == bobID })
        try await alice.decide(on: waiting, admit: true)
        #expect(alice.roster(of: room).members.contains(bobID))

        let carol = TestSession.make(clock: clock)
        await carol.load()
        try await carol.createIdentity(displayName: "Carol")
        let ignored = try await alice.invite(
            joinerCode: carol.identityCode(), joining: room, mailbox: nil, lasting: .aDay)
        clock.advance(by: 2 * day)

        let carolID = try #require(carol.enrolment?.identity.id)
        #expect(
            !alice.pendingJoins(in: room).contains { $0.joiner == carolID },
            "the room offered a decision on an offer nobody had answered and that had run out")
        await #expect(throws: MembershipError.expired) {
            try await alice.decide(on: ignored.attestation, admit: true)
        }
    }

    @Test("An offer somebody took is not an offer that ran out")
    func aTakenOfferIsNotALapsedOne() throws {
        let founder = Identity.generate()
        let answered = Identity.generate()
        let ignored = Identity.generate()
        var roster = try founded(by: founder, access: .founder)

        let taken = try TestInvite.issue(
            joining: room, joinerKeys: answered.publicKeys, by: founder, at: start, lasting: .aDay)
        let untaken = try TestInvite.issue(
            joining: room, joinerKeys: ignored.publicKeys, by: founder, at: start, lasting: .aDay)
        for (hash, attestation) in [(UInt8(2), taken), (UInt8(3), untaken)] {
            roster.apply(
                rendered(founder.id, .joinRequest, hash: hash),
                body: try Payload.joinRequest(attestation))
        }
        roster.apply(
            rendered(founder.id, .joinConfirmed, hash: 4),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: taken, by: answered)))

        let afterwards = start.addingTimeInterval(2 * day)
        #expect(
            roster.pendingInvitations(at: afterwards).map(\.joiner) == [answered.id],
            "a confirmed invitation was dropped from what the room is waiting on")
        #expect(
            roster.lapsedInvitations(at: afterwards).map(\.joiner) == [ignored.id],
            "a confirmed invitation was drawn as one nobody answered")
    }

    @Test("An offer taken but never approved can still be taken back after the date")
    @MainActor
    func aTakenOfferCanStillBeWithdrawn() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: start)
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.setAccess(.founder, in: room)
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil, lasting: .aDay)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<6 {
            try await bob.sync(through: mailbox)
            try await alice.sync(through: mailbox)
        }

        clock.advance(by: 2 * day)
        let bobID = try #require(bob.enrolment?.identity.id)
        #expect(
            alice.pendingInvitations(in: room).contains { $0.joiner == bobID },
            "the one row carrying Take back the invitation was gone")

        try await alice.rescind(invite.attestation)
        for _ in 0..<6 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(alice.roster(of: room).wasRescinded(bobID))
        for session in [alice, bob] {
            #expect(!session.roster(of: room).members.contains(bobID))
        }
    }

    // MARK: The joiner's side of it

    @Test("A joiner is told the invitation ran out rather than watching the row go")
    @MainActor
    func theJoinerIsToldItRanOut() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: start)
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.setAccess(.founder, in: room)
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil, lasting: .aDay)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await bob.sync(through: mailbox)
            try await alice.sync(through: mailbox)
        }
        let waiting = try #require(bob.awaitingAdmission.first)
        #expect(!waiting.hasLapsed, "precondition: Bob is waiting on a live invitation")

        clock.advance(by: 2 * day)
        for _ in 0..<4 {
            try await bob.sync(through: mailbox)
            try await alice.sync(through: mailbox)
        }

        let afterwards = try #require(
            bob.awaitingAdmission.first, "the joiner's only view of that room simply left")
        #expect(afterwards.hasLapsed)
        #expect(afterwards.phrase == waiting.phrase, "the six characters went with the row")
    }

    @Test("Somebody already in the room is waiting for nothing")
    @MainActor
    func aMemberIsNotWaiting() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: start)
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil, lasting: .aDay)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<6 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        clock.advance(by: 7 * day)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(bob.roster(of: room).members.contains(try #require(bob.enrolment?.identity.id)))
        #expect(bob.awaitingAdmission.isEmpty, "somebody in the room was still listed as waiting")
    }

    // MARK: The half that was already enforced, stated once

    @Test("The device holding a lapsed invitation will not use it")
    @MainActor
    func theHolderRefusesIt() async throws {
        let clock = TestClock(now: start)
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil, lasting: .aDay)
        clock.advance(by: 2 * day)

        #expect(bob.inspect(inviteCode: try invite.encoded()) == nil)
        await #expect(throws: (any Error).self) {
            try await bob.redeem(inviteCode: try invite.encoded())
        }
        await #expect(throws: MembershipError.expired) {
            try await bob.accept(
                invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        }
    }
}
