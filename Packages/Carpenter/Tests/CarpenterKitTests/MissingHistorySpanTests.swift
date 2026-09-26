import Foundation
import Testing

@testable import CarpenterKit

@Suite("Spans of missing history")
struct MissingHistorySpanTests {
    private func spans(_ random: inout Seeded) -> [SequenceSpan] {
        (0..<Int.random(in: 0...5, using: &random)).map { _ in
            let lower = UInt64.random(in: 1...40, using: &random)
            return SequenceSpan(lower, lower + UInt64.random(in: 0...8, using: &random))
        }
    }

    private func members(_ spans: [SequenceSpan]) -> Set<UInt64> {
        Set(spans.flatMap { Array($0.lower...$0.upper) })
    }

    private func isNormal(_ spans: [SequenceSpan]) -> Bool {
        zip(spans, spans.dropFirst()).allSatisfy { $0.upper + 1 < $1.lower }
    }

    @Test("Joining, crossing and cutting spans agrees with doing it one number at a time")
    func spanArithmeticMatchesCounting() {
        var random = Seeded(state: 26)
        for _ in 0..<300 {
            let (left, right) = (spans(&random), spans(&random))

            #expect(members(left.normalized) == members(left))
            #expect(isNormal(left.normalized))
            #expect(members(left.intersecting(right)) == members(left).intersection(members(right)))
            #expect(isNormal(left.intersecting(right)))
            #expect(members(left.subtracting(right)) == members(left).subtracting(members(right)))
            #expect(isNormal(left.subtracting(right)))
            #expect(left.normalized.sequenceCount == UInt64(members(left).count))
        }
    }

    @Test("Gaps cross and cut by feed the way their numbers do")
    func gapArithmeticMatchesCounting() {
        var random = Seeded(state: 9)
        let feeds = (1...2).map { FeedKey(author: ParticipantID(rawValue: Data([$0])), device: DeviceID(rawValue: Data([$0]))) }
        for _ in 0..<200 {
            let mine = feeds.map { FeedGap(feed: $0, spans: spans(&random).normalized) }.filter { !$0.spans.isEmpty }
            let theirs = feeds.map { FeedGap(feed: $0, spans: spans(&random).normalized) }.filter { !$0.spans.isEmpty }
            for feed in feeds {
                let a = members(mine.spans(of: feed))
                let b = members(theirs.spans(of: feed))
                #expect(members(mine.intersecting(theirs).spans(of: feed)) == a.intersection(b))
                #expect(members(mine.subtracting(theirs).spans(of: feed)) == a.subtracting(b))
            }
            var grown = mine
            let added = UInt64.random(in: 1...50, using: &random)
            grown.insert(feeds[0], added)
            #expect(members(grown.spans(of: feeds[0])) == members(mine.spans(of: feeds[0])).union([added]))
        }
    }

    @Test("A span over every sequence number is counted without overflowing")
    func everySequenceNumberCounts() {
        let everything = SequenceSpan(1, .max)
        #expect(everything.count == .max)

        let feed = FeedKey(author: ParticipantID(rawValue: Data([1])), device: DeviceID(rawValue: Data([1])))
        let gaps = [FeedGap(feed: feed, spans: [everything]), FeedGap(feed: feed, spans: [SequenceSpan(1, 9)])]
        #expect(gaps[0].count == .max)
        #expect(gaps.total == .max)
    }

    @Test("A span a peer sends backwards counts nothing and contains nothing")
    func aBackwardsSpanIsEmpty() throws {
        let backwards = try JSONDecoder().decode(SequenceSpan.self, from: Data(#"{"lower":9,"upper":2}"#.utf8))

        #expect(backwards.count == 0)
        #expect(!backwards.contains(5))
        #expect([backwards].normalized.isEmpty)
        #expect([SequenceSpan(1, 20)].subtracting([backwards]) == [SequenceSpan(1, 20)])
    }
}

@Suite("History somebody else can claim")
struct ClaimedHistoryTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func entry(by author: Author, at seq: UInt64) throws -> Entry {
        let payload = try Payload.post("far away").sealed(at: .initial, using: author.chain)
        let unsigned = Entry(
            author: author.identity.id, device: author.device.id, seq: seq,
            previous: EntryHash(rawValue: Data(repeating: 7, count: 32)), clock: VectorClock(),
            wallTime: start, room: nil, payload: payload, signature: Data())
        return Entry(
            author: unsigned.author, device: unsigned.device, seq: seq, previous: unsigned.previous,
            clock: unsigned.clock, wallTime: start, room: nil, payload: payload,
            signature: try author.device.sign(unsigned.signingPayload))
    }

    @Test("An entry signed at a sequence number no feed will reach does not stop the gaps being found")
    func aFarEntryLeavesGapsCheap() throws {
        var replica = Replica()
        var alice = Author()
        try replica.meet(alice)
        for step in 0..<3 { try replica.integrate(try alice.post("\(step)", at: start)) }
        try replica.integrate(try entry(by: alice, at: 1 << 50))

        let started = Date()
        let gaps = replica.gaps()

        #expect(Date().timeIntervalSince(started) < 1)
        #expect(gaps == [FeedGap(feed: alice.feedKey, spans: [SequenceSpan(4, (1 << 50) - 1)])])
    }

    @Test("A request for every sequence number is answered from what is held")
    func askingForEverythingIsCheap() throws {
        var replica = Replica()
        var alice = Author()
        try replica.meet(alice)
        var held: [Entry] = []
        for step in 0..<5 {
            let made = try alice.post("\(step)", at: start)
            try replica.integrate(made)
            held.append(made)
        }
        let request = RepairRequest(
            authors: [], heads: VectorClock(),
            gaps: [FeedGap(feed: alice.feedKey, spans: [SequenceSpan(1, .max)])])

        let started = Date()
        let (entries, unheld) = replica.fill(request)

        #expect(Date().timeIntervalSince(started) < 1)
        #expect(entries == held)
        #expect(unheld == [FeedGap(feed: alice.feedKey, spans: [SequenceSpan(6, .max)])])
    }

    @Test("A request whose heads claim the last sequence number is answered with nothing, not a crash")
    func headsAtTheEndOfTime() throws {
        var replica = Replica()
        var alice = Author()
        try replica.meet(alice)
        try replica.integrate(try alice.post("hello", at: start))
        var heads = VectorClock()
        heads.observe(alice.feedKey, seq: .max)

        let (entries, unheld) = replica.fill(
            RepairRequest(authors: [alice.identity.id], heads: heads, gaps: []))

        #expect(entries.isEmpty)
        #expect(unheld.isEmpty)
    }
}
