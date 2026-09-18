@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("How long a free year lasts")
struct SupporterStandingTests {
    private let claimed = Date(timeIntervalSince1970: 1_786_635_000)

    @Test("Nobody who has not claimed the year is a Supporter")
    func unclaimed() {
        for channel in [DistributionChannel.testFlight, .appStore, .development] {
            #expect(SupporterStanding.of(claimedAt: nil, startedAt: nil, channel: channel, now: claimed) == .none)
        }
    }

    @Test("Before release the year has not started, so it has no end")
    func openBeforeRelease() {
        let later = claimed.addingTimeInterval(400 * 86_400)
        #expect(
            SupporterStanding.of(claimedAt: claimed, startedAt: nil, channel: .testFlight, now: later)
                == .testFlightYear(endsAt: nil))
    }

    @Test("On the App Store the year runs from the day it started")
    func runsFromTheStart() throws {
        let start = claimed.addingTimeInterval(90 * 86_400)
        let standing = SupporterStanding.of(
            claimedAt: claimed, startedAt: start, channel: .appStore, now: start.addingTimeInterval(86_400))
        guard case .testFlightYear(let end?) = standing else {
            Issue.record("expected a year with an end, got \(standing)")
            return
        }
        let days = end.timeIntervalSince(start) / 86_400
        #expect(days == 365 || days == 366)
    }

    @Test("A year the App Store build has not started yet starts now")
    func startsNow() {
        let standing = SupporterStanding.of(claimedAt: claimed, startedAt: nil, channel: .appStore, now: claimed)
        #expect(standing.isSupporter)
        #expect(standing != .testFlightYear(endsAt: nil))
    }

    @Test("A year that has run out is over, on every build")
    func lapses() {
        let start = claimed
        let after = start.addingTimeInterval(367 * 86_400)
        for channel in [DistributionChannel.testFlight, .appStore, .development] {
            #expect(SupporterStanding.of(claimedAt: claimed, startedAt: start, channel: channel, now: after) == .none)
        }
    }

    @Test("Two devices that both claimed keep the earlier claim, whichever merges first")
    func earlierClaimWins() {
        let first = DeviceID(rawValue: WideID.of([1]))
        let second = DeviceID(rawValue: WideID.of([2]))
        var a = MemberPreferences()
        a.claimSupporterYear(at: claimed, stamp: OrganisationStamp(at: claimed, device: first))
        var b = MemberPreferences()
        let later = claimed.addingTimeInterval(60)
        b.claimSupporterYear(at: later, stamp: OrganisationStamp(at: later, device: second))

        #expect(a.merged(with: b).supporterYearClaimed?.value == claimed)
        #expect(b.merged(with: a).supporterYearClaimed?.value == claimed)
    }
}

@MainActor
@Suite("The Supporter badge", .serialized)
struct SupporterBadgeTests {
    private func joined(clock: TestClock = TestClock(now: TestSession.now)) async throws -> (
        alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox, room: RoomID
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(clock: clock)
        alice.distribution = .testFlight
        bob.distribution = .testFlight
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle(alice, bob, mailbox)
        return (alice, bob, mailbox, room)
    }

    private func settle(_ a: AppSession, _ b: AppSession, _ mailbox: InMemoryMailbox) async throws {
        for _ in 0..<2 {
            try await a.sync(through: mailbox)
            try await b.sync(through: mailbox)
        }
    }

    @Test("The free year is offered on TestFlight and never on the App Store")
    func offeredOnlyOffTheStore() async throws {
        let store = TestSession.make()
        store.distribution = .appStore
        await store.load()
        try await store.createIdentity(displayName: "Store")
        #expect(!store.canClaimSupporterYear)
        await store.claimSupporterYear()
        #expect(!store.isSupporter, "the App Store build granted a year it does not offer")

        let tester = TestSession.make()
        tester.distribution = .testFlight
        await tester.load()
        try await tester.createIdentity(displayName: "Tester")
        #expect(tester.canClaimSupporterYear)
        await tester.claimSupporterYear()
        #expect(tester.isSupporter)
        #expect(!tester.canClaimSupporterYear, "the offer is still showing to somebody who took it")
        #expect(!tester.showsSupporterBadge, "the badge showed before anybody was asked")
    }

    @Test("A shown badge reaches the people in your rooms, and hiding it takes it back")
    func reachesAPeer() async throws {
        let (alice, bob, mailbox, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)

        await alice.setShowsSupporterBadge(true)
        try await settle(alice, bob, mailbox)
        #expect(!bob.supporterBadges.contains(aliceID), "somebody who is not a Supporter showed a badge")

        await alice.claimSupporterYear()
        await alice.refreshSupporterStanding()
        try await settle(alice, bob, mailbox)
        #expect(bob.supporterBadges.contains(aliceID))
        #expect(alice.supporterBadges.contains(aliceID), "your own badge is not drawn for you")

        await alice.setShowsSupporterBadge(false)
        try await settle(alice, bob, mailbox)
        #expect(!bob.supporterBadges.contains(aliceID))
        #expect(!alice.supporterBadges.contains(aliceID))
    }

    @Test("The badge goes into a room you join after turning it on")
    func reachesALaterRoom() async throws {
        let (alice, bob, mailbox, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        await bob.claimSupporterYear()
        await bob.setShowsSupporterBadge(true)

        let second = try await alice.createRoom(named: "Second")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: second, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        for _ in 0..<4 { try await settle(alice, bob, mailbox) }

        let bobID = try #require(bob.enrolment?.identity.id)
        #expect(bob.projection.lastSupporterBadge(of: bobID, in: second)?.shows == true)
        #expect(alice.supporterBadges.contains(bobID))
        #expect(!bob.supporterBadges.contains(aliceID))
    }

    @Test("A blocked person's badge is not drawn")
    func blockedIsNotDrawn() async throws {
        let (alice, bob, mailbox, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        await alice.claimSupporterYear()
        await alice.setShowsSupporterBadge(true)
        try await settle(alice, bob, mailbox)
        #expect(bob.supporterBadges.contains(aliceID))

        await bob.block(aliceID)
        #expect(!bob.supporterBadges.contains(aliceID))
    }

    @Test("When the year runs out on the App Store, the badge is taken back from everybody")
    func lapsedBadgeIsWithdrawn() async throws {
        let clock = TestClock(now: TestSession.now)
        let (alice, bob, mailbox, _) = try await joined(clock: clock)
        let aliceID = try #require(alice.enrolment?.identity.id)
        await alice.claimSupporterYear()
        await alice.setShowsSupporterBadge(true)
        try await settle(alice, bob, mailbox)

        alice.distribution = .appStore
        await alice.refreshSupporterStanding()
        #expect(alice.persisted.preferences.supporterYearStarted?.value == clock.now)
        #expect(alice.isSupporter)
        try await settle(alice, bob, mailbox)
        #expect(bob.supporterBadges.contains(aliceID))

        clock.advance(by: 367 * 86_400)
        await alice.refreshSupporterStanding()
        #expect(!alice.isSupporter)
        try await settle(alice, bob, mailbox)
        #expect(!bob.supporterBadges.contains(aliceID), "a lapsed year kept its badge")
    }
}
