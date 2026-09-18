import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("When a seen mark says it was seen")
struct ReadEvidenceTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    @Test("A message keeps the first receipt that covered it, not the reader's latest")
    func firstNotLatest() {
        let evidence = ReadEvidence([
            .init(position: 3, at: at(0)),
            .init(position: 9, at: at(60)),
        ])
        #expect(evidence.firstCovering(3) == at(0), "the later receipt overwrote an earlier answer")
        #expect(evidence.firstCovering(1) == at(0))
        #expect(evidence.firstCovering(4) == at(60))
        #expect(evidence.firstCovering(9) == at(60))
        #expect(evidence.furthest == 9)
    }

    @Test("A position nobody has reached has no time at all")
    func beyondTheFurthest() {
        let evidence = ReadEvidence([.init(position: 4, at: at(0))])
        #expect(evidence.firstCovering(5) == nil)
        #expect(ReadEvidence([]).firstCovering(0) == nil)
        #expect(ReadEvidence([]).furthest == nil)
        #expect(ReadEvidence([]).isEmpty)
    }

    @Test("A reader who fell behind cannot walk a mark backwards")
    func fallingBehindDoesNotWalkItBack() {
        let evidence = ReadEvidence([
            .init(position: 8, at: at(0)),
            .init(position: 2, at: at(90)),
        ])
        #expect(evidence.firstCovering(8) == at(0))
        #expect(evidence.firstCovering(2) == at(0), "a later receipt for an earlier place moved the mark")
        #expect(evidence.furthest == 8)
    }

    @Test("Evidence that arrives late can only make a mark earlier")
    func lateEvidenceOnlyMovesItEarlier() {
        let known = ReadEvidence([.init(position: 5, at: at(120))])
        #expect(known.firstCovering(5) == at(120))

        let withLate = ReadEvidence([
            .init(position: 5, at: at(120)),
            .init(position: 6, at: at(30)),
        ])
        #expect(withLate.firstCovering(5) == at(30))
        #expect(withLate.furthest == 6)
    }

    @Test("With several readers the earliest of them is the mark")
    func earliestOfSeveralReaders() {
        let evidence = ReadEvidence([
            .init(position: 7, at: at(45)),
            .init(position: 7, at: at(10)),
            .init(position: 2, at: at(5)),
        ])
        #expect(evidence.firstCovering(7) == at(10))
        #expect(evidence.firstCovering(2) == at(5))
    }

    @Test("The folded answer agrees with the plain one, whatever order the receipts arrive in")
    func agreesWithBruteForce() {
        let raw: [ReadEvidence.Mark] = (0..<40).map { index in
            .init(position: (index * 17) % 23, at: at(Double((index * 29) % 37)))
        }
        for rotation in 0..<7 {
            let shuffled = Array(raw[rotation...] + raw[..<rotation])
            let evidence = ReadEvidence(shuffled)
            for position in 0...25 {
                let expected = shuffled.filter { $0.position >= position }.map(\.at).min()
                #expect(
                    evidence.firstCovering(position) == expected,
                    "position \(position) disagreed at rotation \(rotation)")
            }
            #expect(evidence.furthest == shuffled.map(\.position).max())
        }
    }
}

@MainActor
@Suite("A seen mark through the fold", .serialized)
struct SeenMarkTimeTests {
    @Test("Each message carries the instant its own first receipt was written")
    func eachMessageKeepsItsOwnInstant() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = AppSession(storage: TestSession.storage(), clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        await bob.setReportsDisplaying(true)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        try await alice.send("first", to: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        let first = try #require(bob.messages(in: room).first { $0.body == "first" })
        await bob.markSeen(first.id, in: room)
        let firstSeenAt = clock.now
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        clock.advance(by: 3600)
        try await alice.send("second", to: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        let second = try #require(bob.messages(in: room).first { $0.body == "second" })
        await bob.markSeen(second.id, in: room)
        let secondSeenAt = clock.now
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        let mine = alice.messages(in: room)
        let one = try #require(mine.first { $0.body == "first" })
        let two = try #require(mine.first { $0.body == "second" })
        #expect(
            one.delivery.displayedAt == firstSeenAt,
            "the first message borrowed the later receipt's time: \(String(describing: one.delivery))")
        #expect(two.delivery.displayedAt == secondSeenAt)
    }
}
