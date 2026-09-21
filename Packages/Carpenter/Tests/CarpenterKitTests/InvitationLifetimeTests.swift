@testable import CarpenterKit
import Foundation
import Testing
import CarpenterKitTesting

@Suite("How long an invitation lasts")
struct InvitationLifetimeTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func attestation(
        lasting lifetime: InvitationLifetime, at issued: Date? = nil
    ) throws -> MembershipAttestation {
        try TestInvite.issue(
            joining: ConversationID.room(UUID()), joinerKeys: Identity.generate().publicKeys,
            by: Identity.generate(), at: issued ?? start, lasting: lifetime)
    }

    @Test("Each choice lapses when it says it will")
    func eachChoiceExpiresWhenStated() throws {
        let day: TimeInterval = 24 * 60 * 60

        #expect(try attestation(lasting: .aDay).expiresAt == start.addingTimeInterval(day))
        #expect(try attestation(lasting: .aWeek).expiresAt == start.addingTimeInterval(7 * day))
        #expect(try attestation(lasting: .thirtyDays).expiresAt == start.addingTimeInterval(30 * day))

        let picked = start.addingTimeInterval(12345)
        #expect(try attestation(lasting: .until(picked)).expiresAt == picked)
    }

    @Test("A lifetime means the same number of seconds wherever it is read")
    func lifetimesAreFixedIntervals() throws {
        let inSydney = Date(timeIntervalSince1970: 1_800_000_000)
        let atNewYear = Date(timeIntervalSince1970: 1_767_225_600)

        for issued in [start, inSydney, atNewYear] {
            let lapse = try attestation(lasting: .thirtyDays, at: issued).expiresAt
            #expect(
                lapse.timeIntervalSince(issued) == 30 * 24 * 60 * 60,
                "thirty days meant something different depending on when it started")
        }
    }

    @Test("An indefinite invitation never lapses, and says so")
    func indefiniteNeverLapses() throws {
        let forever = try attestation(lasting: .indefinite)

        #expect(!forever.hasLapsed(at: start.addingTimeInterval(100 * 365 * 24 * 60 * 60)))
        #expect(InvitationLifetime.indefinite.isIndefinite)
        #expect(!InvitationLifetime.aDay.isIndefinite)
        #expect(InvitationLifetime.until(.distantFuture).isIndefinite, "a picked forever is forever")
    }

    @Test("Lapsing is decided by the instant it is asked about")
    func lapsingIsDeterministic() throws {
        let oneDay = try attestation(lasting: .aDay)

        #expect(!oneDay.hasLapsed(at: start))
        #expect(!oneDay.hasLapsed(at: oneDay.expiresAt.addingTimeInterval(-1)))
        #expect(oneDay.hasLapsed(at: oneDay.expiresAt), "the moment it expires, it has expired")
        #expect(oneDay.hasLapsed(at: oneDay.expiresAt.addingTimeInterval(1)))
    }

    @Test("The offered choices are the fixed ones")
    func offeredChoices() {
        #expect(InvitationLifetime.allCases == [.aDay, .aWeek, .thirtyDays, .indefinite])
        #expect(!InvitationLifetime.allCases.contains { if case .until = $0 { true } else { false } })
        #expect(InvitationLifetime.until(.distantPast).isPickedDate)
        #expect(!InvitationLifetime.aWeek.isPickedDate)
    }

    @Test("A picked day is good until the end of that day, in the zone it was picked in")
    func aPickedDayLastsAllDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        let sydney = try #require(TimeZone(identifier: "Australia/Sydney"))
        calendar.timeZone = sydney

        let noon = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12)))
        let lifetime = InvitationLifetime.endOfDay(noon, in: calendar)
        let expiry = lifetime.expiry(from: start)

        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: expiry)
        #expect(components.day == 14, "a picked day ended on a different day")
        #expect(components.hour == 23 && components.minute == 59)

        #expect(expiry > noon)
        #expect(expiry.timeIntervalSince(noon) < 12 * 60 * 60)

        var elsewhere = Calendar(identifier: .gregorian)
        elsewhere.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let there = try #require(
            elsewhere.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12)))
        #expect(
            InvitationLifetime.endOfDay(there, in: elsewhere).expiry(from: start) != expiry,
            "two zones resolved one calendar day to the same instant")
    }

    @Test("A picked date runs out, and a picked forever does not")
    func aPickedDateStillLapses() throws {
        let nextYear = start.addingTimeInterval(365 * 24 * 60 * 60)
        let picked = InvitationLifetime.until(nextYear)

        #expect(!picked.isIndefinite)
        #expect(picked.isPickedDate)
        let attestation = try attestation(lasting: picked)
        #expect(!attestation.hasLapsed(at: nextYear.addingTimeInterval(-1)))
        #expect(attestation.hasLapsed(at: nextYear))
    }
}

@Suite("Invitations a room is still waiting on")
struct PendingInvitationTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let room = ConversationID.room(UUID())

    private func rendered(
        _ author: ParticipantID, _ type: PayloadType, hash: UInt8
    ) -> RenderedEntry {
        RenderedEntry(
            id: EntryHash(rawValue: Data(repeating: hash, count: 32)), type: type, author: author,
            device: DeviceID(rawValue: WideID.of([])), wallTime: start, conversation: room, content: .text(""),
            editedAt: nil, replyingTo: nil, reactions: [:])
    }

    private func roomWith(
        founder: Identity, inviting joiners: [(Identity, InvitationLifetime)]
    ) throws -> RoomRoster {
        var roster = RoomRoster(room: room)
        var hash: UInt8 = 1
        roster.apply(
            rendered(founder.id, .roomProfile, hash: hash),
            body: try Payload.roomProfile(name: "Hangar 7"))
        roster.set(access: .founder, by: founder.id)
        for (joiner, lifetime) in joiners {
            hash += 1
            let invite = try TestInvite.issue(
                joining: room, joinerKeys: joiner.publicKeys, by: founder, at: start,
                lasting: lifetime)
            roster.apply(
                rendered(founder.id, .joinRequest, hash: hash),
                body: try Payload.joinRequest(invite))
        }
        return roster
    }

    @Test("An invitation waiting is listed, with who sent it and when it lapses")
    func waitingIsListed() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()

        let roster = try roomWith(founder: alice, inviting: [(bob, .aWeek)])
        let pending = roster.pendingInvitations(at: start)

        #expect(pending.count == 1)
        #expect(pending.first?.joiner == bob.id)
        #expect(pending.first?.invitedBy == alice.id)
        #expect(pending.first?.expiresAt == start.addingTimeInterval(7 * 24 * 60 * 60))
        #expect(pending.first?.isIndefinite == false)
    }

    @Test("An invitation that ran out is still readable, and is not still waiting")
    func lapsedIsKeptAndNotPending() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let roster = try roomWith(founder: alice, inviting: [(bob, .aDay)])
        let afterwards = start.addingTimeInterval(2 * 24 * 60 * 60)

        #expect(roster.pendingInvitations(at: afterwards).isEmpty, "a dead offer counted as waiting")
        #expect(roster.lapsedInvitations(at: afterwards).map(\.joiner) == [bob.id])
        #expect(roster.lapsedInvitations(at: afterwards).first?.invitedBy == alice.id)

        #expect(roster.pendingInvitations(at: start).count == 1)
        #expect(roster.lapsedInvitations(at: start).isEmpty)
    }

    @Test("Joining or taking it back leaves nothing in either list")
    func neitherListKeepsASettledOffer() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let afterwards = start.addingTimeInterval(2 * 24 * 60 * 60)

        var joined = try roomWith(founder: alice, inviting: [(bob, .aDay)])
        let invitation = try #require(joined.requests[bob.id])
        joined.apply(
            rendered(alice.id, .joinConfirmed, hash: 60),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: invitation, by: bob)))
        joined.apply(
            rendered(alice.id, .admission, hash: 61),
            body: try Payload.admission(of: bob.id, admitted: true))
        #expect(joined.lapsedInvitations(at: afterwards).isEmpty, "somebody in the room was listed as a dead offer")

        var withdrawn = try roomWith(founder: alice, inviting: [(bob, .aDay)])
        let withdrawnOffer = try #require(withdrawn.requests[bob.id])
        withdrawn.apply(
            rendered(alice.id, .invitationRescinded, hash: 62),
            body: try Payload.invitationRescinded(of: withdrawnOffer))
        #expect(
            withdrawn.lapsedInvitations(at: afterwards).isEmpty,
            "an invitation taken back came back as one that ran out")
    }

    @Test("Somebody who joined is no longer waiting")
    func joiningClearsIt() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()

        var roster = try roomWith(founder: alice, inviting: [(bob, .aWeek)])
        #expect(roster.pendingInvitations(at: start).count == 1)

        let invitation = try #require(roster.requests[bob.id])
        roster.apply(
            rendered(alice.id, .joinConfirmed, hash: 49),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: invitation, by: bob)))
        roster.apply(
            rendered(alice.id, .admission, hash: 50),
            body: try Payload.admission(of: bob.id, admitted: true))

        #expect(roster.members.contains(bob.id))
        #expect(
            roster.pendingInvitations(at: start).isEmpty,
            "a member was still listed as an outstanding invitation")
    }

    @Test("A lapsed invitation stops being listed")
    func lapsedDropsOut() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()

        let roster = try roomWith(founder: alice, inviting: [(bob, .aDay)])
        let day: TimeInterval = 24 * 60 * 60

        #expect(roster.pendingInvitations(at: start.addingTimeInterval(day - 1)).count == 1)
        #expect(roster.pendingInvitations(at: start.addingTimeInterval(day)).isEmpty)
    }

    @Test("An indefinite invitation is still waiting a century later, and says so")
    func indefiniteKeepsWaiting() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()

        let roster = try roomWith(founder: alice, inviting: [(bob, .indefinite)])
        let aCentury = start.addingTimeInterval(100 * 365 * 24 * 60 * 60)

        #expect(roster.pendingInvitations(at: aCentury).count == 1)
        #expect(roster.pendingInvitations(at: aCentury).first?.isIndefinite == true)
    }

    @Test("Invitations issued in the same moment are listed in the same order everywhere")
    func orderIsStable() throws {
        let alice = Identity.generate()
        let invited = (0..<8).map { _ in Identity.generate() }

        let roster = try roomWith(founder: alice, inviting: invited.map { ($0, .aWeek) })
        let once = roster.pendingInvitations(at: start).map(\.joiner)
        let again = roster.pendingInvitations(at: start).map(\.joiner)

        #expect(once.count == 8)
        #expect(once == again)
        #expect(once == once.sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) })
    }
}
