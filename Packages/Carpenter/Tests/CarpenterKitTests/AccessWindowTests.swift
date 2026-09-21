import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("What a reader may read, stretch by stretch", .serialized)
struct AccessWindowSessionTests {
    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func acquainted() async throws -> (AppSession, AppSession, InMemoryMailbox) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        for one in [alice, bob] { await one.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(
            invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle([alice, bob], through: mailbox)
        return (alice, bob, mailbox)
    }

    @Test("A reader let in, stopped and let in again reads two stretches and not the gap")
    func gapsAreRealInTheKeySchedule() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let alice = AppSession(storage: TestSession.storage(), clock: clock)
        let bob = AppSession(storage: TestSession.storage(), clock: clock)
        for one in [alice, bob] { await one.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(
            invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle([alice, bob], through: mailbox)

        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.send("one, before anything", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        clock.advance(by: 60)
        try await alice.allowOutpost(bobID, everything: false)
        try await alice.send("two, first stretch", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        clock.advance(by: 60)
        try await alice.revokeOutpost(bobID)
        try await alice.send("three, in the gap", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        clock.advance(by: 60)
        try await alice.allowOutpost(bobID, everything: false)
        try await alice.send("four, second stretch", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        let read = bob.feed().map(\.body)
        #expect(read.contains("two, first stretch"), "the first stretch was lost")
        #expect(read.contains("four, second stretch"), "the second stretch never arrived")
        #expect(!read.contains("one, before anything"), "he read from before his first stretch")
        #expect(!read.contains("three, in the gap"), "he read the gap")

        let windows = try #require(alice.outpostAccess.grant(for: bobID)?.windows)
        #expect(windows.count == 2, "two stretches were folded as one")
        #expect(windows[0].until != nil, "the first stretch never closed")
        #expect(windows[1].isOpen, "the second stretch is not open")
    }

    @Test("Everything replaces the stretches rather than sitting beside them")
    func everythingSubsumes() async throws {
        let (alice, bob, mailbox) = try await acquainted()
        let bobID = try #require(bob.enrolment?.identity.id)

        try await alice.allowOutpost(bobID, everything: false)
        try await alice.revokeOutpost(bobID)
        try await alice.allowOutpost(bobID, everything: true)
        try await settle([alice, bob], through: mailbox)

        let windows = try #require(alice.outpostAccess.grant(for: bobID)?.windows)
        #expect(windows == [AccessWindow()], "everything left an earlier stretch beside it")
        #expect(alice.outpostAccess.standing(for: bobID) == .everything)
    }

    @Test("Stopping closes the stretch and keeps it")
    func stoppingKeepsTheRecord() async throws {
        let (alice, bob, mailbox) = try await acquainted()
        let bobID = try #require(bob.enrolment?.identity.id)

        try await alice.allowOutpost(bobID, everything: true)
        try await alice.revokeOutpost(bobID)
        try await settle([alice, bob], through: mailbox)

        let windows = try #require(alice.outpostAccess.grant(for: bobID)?.windows)
        #expect(windows.count == 1)
        #expect(windows[0].from == nil, "the stretch forgot that it covered everything")
        #expect(windows[0].until == TestSession.now, "it did not close where it was closed")
        #expect(alice.outpostAccess.standing(for: bobID) == .none)
    }
}

@Suite("Which changes are on offer")
struct AccessStandingTests {
    private let when = Date(timeIntervalSince1970: 1_775_260_800)

    @Test("Nothing yet: start a stretch, or give everything")
    func fromNone() {
        #expect(OutpostAccess.Standing.none.offers == [.fromNow, .everything])
    }

    @Test("A stretch open: stop it, or give everything")
    func fromAStretch() {
        #expect(OutpostAccess.Standing.from(when).offers == [.no, .everything])
    }

    @Test("Everything: the only change left is stopping")
    func fromEverything() {
        #expect(OutpostAccess.Standing.everything.offers == [.no])
        #expect(!OutpostAccess.Standing.everything.offers.contains(.fromNow))
    }

    @Test("Only everything is a door that does not open both ways")
    func finality() {
        #expect(OutpostAccess.Standing.isFinal(.everything))
        #expect(!OutpostAccess.Standing.isFinal(.fromNow))
        #expect(!OutpostAccess.Standing.isFinal(.no))
    }

    @Test("Where somebody stands is read from the stretch still growing")
    func standing() {
        #expect(OutpostAccess.Standing(nil) == .none)
        #expect(OutpostAccess.Standing(OutpostAccess.Grant(windows: [])) == .none)
        #expect(OutpostAccess.Standing(OutpostAccess.Grant()) == .everything)
        #expect(OutpostAccess.Standing(OutpostAccess.Grant(from: when)) == .from(when))
        #expect(
            OutpostAccess.Standing(
                OutpostAccess.Grant(windows: [AccessWindow(from: when, until: when)])) == .none,
            "a stretch that has ended read as one still growing")
    }

    @Test("A stretch covers its first instant and not its last")
    func boundaries() {
        let window = AccessWindow(from: when, until: when.addingTimeInterval(60))
        #expect(window.contains(when))
        #expect(window.contains(when.addingTimeInterval(59)))
        #expect(!window.contains(when.addingTimeInterval(60)))
        #expect(!window.contains(when.addingTimeInterval(-1)))
    }
}

@Suite("Stretches, said as dates")
struct AccessWindowsCopyTests {
    private let march = Date(timeIntervalSince1970: 1_772_000_000)
    private let july = Date(timeIntervalSince1970: 1_784_000_000)

    @Test("A stretch still growing ends in the present, never in today's date")
    func openEndsInThePresent() {
        let line = AccessWindowsCopy.line(for: AccessWindow(from: march))
        #expect(line.hasSuffix("present"))
        #expect(line.contains("–"), "a range was not drawn as a range")
    }

    @Test("A stretch that has ended is two dates")
    func closedIsTwoDates() {
        let line = AccessWindowsCopy.line(for: AccessWindow(from: march, until: july))
        #expect(!line.contains("present"))
        #expect(line.contains("–"))
    }

    @Test("Everything says so rather than inventing a first date")
    func everythingIsNotADate() {
        #expect(AccessWindowsCopy.line(for: AccessWindow()) == "Everything")
        let closed = AccessWindowsCopy.line(for: AccessWindow(until: july))
        #expect(closed.hasPrefix("Everything up to"))
    }

    @Test("One line per stretch, oldest first")
    func oneLineEach() {
        let lines = AccessWindowsCopy.lines(for: [
            AccessWindow(from: march, until: july), AccessWindow(from: july),
        ])
        #expect(lines.count == 2)
        #expect(lines[1].hasSuffix("present"), "the newest stretch is not last")
    }

    @Test("A row leads with what is still growing and counts the rest")
    func summary() {
        #expect(AccessWindowsCopy.summary(for: []) == "No access")
        #expect(AccessWindowsCopy.summary(for: [AccessWindow()]) == "Everything")

        let several = AccessWindowsCopy.summary(for: [
            AccessWindow(from: march, until: july), AccessWindow(from: july),
        ])
        #expect(several.hasSuffix("present, and 1 earlier stretch"))
    }
}
