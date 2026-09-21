import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("What each of us can read of the other", .serialized)
struct ReciprocalAccessTests {
    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func acquainted(
        roomNamed name: String = "Zeppelin Enthusiasts"
    ) async throws -> (alice: AppSession, bob: AppSession, room: ConversationID, mailbox: InMemoryMailbox) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        for one in [alice, bob] { await one.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: name)
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(
            invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle([alice, bob], through: mailbox)
        return (alice, bob, room, mailbox)
    }

    @Test("Two people who have decided nothing read nothing of each other")
    func nothingEitherWay() async throws {
        let (alice, bob, _, _) = try await acquainted()
        let bobID = try #require(bob.enrolment?.identity.id)
        let both = try #require(alice.reciprocalAccess(with: bobID))

        #expect(both.youCanRead.isEmpty)
        #expect(both.theyCanRead.isEmpty)
        #expect(!both.isOneSided, "nothing either way is not one-sided, it is symmetrical")
        #expect(both.sharedRooms == ["Zeppelin Enthusiasts"])
    }

    @Test("A solo with them is not listed as a room you share")
    func solosAreNotContext() async throws {
        let (alice, bob, _, mailbox) = try await acquainted()
        let bobID = try #require(bob.enrolment?.identity.id)

        let solo = try await alice.createRoom(named: "Bob", kind: .solo)
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: solo, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(
            invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle([alice, bob], through: mailbox)

        let both = try #require(alice.reciprocalAccess(with: bobID))
        #expect(
            both.sharedRooms == ["Zeppelin Enthusiasts"],
            "a solo with this person was offered as context about this person")
    }

    @Test("What they gave you is read from their wall, not guessed at")
    func theirSideIsRead() async throws {
        let (alice, bob, _, mailbox) = try await acquainted()
        let aliceID = try #require(alice.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)

        try await bob.allowOutpost(aliceID, everything: true)
        try await settle([alice, bob], through: mailbox)

        let both = try #require(alice.reciprocalAccess(with: bobID))
        #expect(both.youCanRead == [AccessWindow()])
        #expect(both.theyCanRead.isEmpty, "Alice's own side moved when Bob decided his")
        #expect(both.isOneSided)
    }

    @Test("Letting somebody in does not let you in")
    func theTwoDirectionsAreIndependent() async throws {
        let (alice, bob, _, mailbox) = try await acquainted()
        let aliceID = try #require(alice.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)

        try await alice.allowOutpost(bobID, everything: true)
        try await settle([alice, bob], through: mailbox)

        let hers = try #require(alice.reciprocalAccess(with: bobID))
        #expect(hers.theyCanRead == [AccessWindow()])
        #expect(hers.youCanRead.isEmpty, "granting access granted her some in return")

        let his = try #require(bob.reciprocalAccess(with: aliceID))
        #expect(his.youCanRead == [AccessWindow()])
        #expect(his.theyCanRead.isEmpty)
    }

    @Test("A from-now grant reads as the date it started")
    func fromNowIsADate() async throws {
        let (alice, bob, _, mailbox) = try await acquainted()
        let aliceID = try #require(alice.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)

        try await bob.allowOutpost(aliceID, everything: false)
        try await settle([alice, bob], through: mailbox)

        let both = try #require(alice.reciprocalAccess(with: bobID))
        let window = try #require(both.youCanRead.last)
        #expect(window.from == TestSession.now)
        #expect(window.isOpen, "a from-now grant did not read as still collecting")
    }

    @Test("Somebody revoked sees that they were, rather than the access they had")
    func revocationIsVisibleToTheRevoked() async throws {
        let (alice, bob, _, mailbox) = try await acquainted()
        let aliceID = try #require(alice.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)

        try await bob.allowOutpost(aliceID, everything: true)
        try await settle([alice, bob], through: mailbox)
        #expect(alice.reciprocalAccess(with: bobID)?.youCanRead == [AccessWindow()])

        try await bob.revokeOutpost(aliceID)
        try await settle([alice, bob], through: mailbox)

        let after = try #require(alice.reciprocalAccess(with: bobID))
        #expect(
            after.yourStanding == .none || OutpostAccess.Standing(after.theyGave) == .none)
        #expect(
            after.youCanRead.allSatisfy { !$0.isOpen },
            "her card still claimed access she no longer has")
        #expect(after.youCanRead.count == 1, "the stretch she did have was forgotten")
    }

    @Test("Two people with no room in common still have two directions")
    func noRoomInCommon() async throws {
        let (alice, bob, room, mailbox) = try await acquainted()
        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        try await settle([alice, bob], through: mailbox)

        try await alice.leave(room)
        try await settle([alice, bob], through: mailbox)

        let both = try #require(alice.reciprocalAccess(with: bobID))
        #expect(both.sharedRooms.isEmpty)
        #expect(
            both.theyCanRead == [AccessWindow()],
            "leaving a room took back a grant it never gave")
    }

    @Test("Nobody has two directions with themselves")
    func notYourself() async throws {
        let (alice, _, _, _) = try await acquainted()
        let me = try #require(alice.enrolment?.identity.id)
        #expect(alice.reciprocalAccess(with: me) == nil)
    }
}

@Suite("What one direction amounts to")
struct ReciprocalReachTests {
    private let when = Date(timeIntervalSince1970: 1_775_260_800)
    private var person: Member {
        Member(id: ParticipantID(rawValue: Data(repeating: 5, count: 32)), displayName: "Camilla")
    }

    @Test("No grant at all and a refusal both read as nothing")
    func nothingIsNothing() {
        #expect(ReciprocalAccess(person: person).youCanRead.isEmpty)
        #expect(
            ReciprocalAccess(person: person, theyGave: OutpostAccess.Grant(isAllowed: false))
                .youCanRead.isEmpty)
    }

    @Test("A grant with no date is one open stretch over everything")
    func everythingAndFrom() {
        let all = ReciprocalAccess(person: person, theyGave: OutpostAccess.Grant())
        #expect(all.youCanRead == [AccessWindow()])

        let dated = ReciprocalAccess(person: person, theyGave: OutpostAccess.Grant(from: when))
        #expect(dated.youCanRead == [AccessWindow(from: when)])
    }

    @Test("The two sides are compared, never ranked")
    func oneSidedness() {
        let same = ReciprocalAccess(
            person: person, theyGave: OutpostAccess.Grant(), youGave: OutpostAccess.Grant())
        #expect(!same.isOneSided)

        let lopsided = ReciprocalAccess(
            person: person, theyGave: OutpostAccess.Grant(),
            youGave: OutpostAccess.Grant(from: when))
        #expect(lopsided.isOneSided)

        let neither = ReciprocalAccess(person: person)
        #expect(!neither.isOneSided, "two people who have decided nothing are not lopsided")
    }
}
