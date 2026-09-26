import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Causal order")
struct CausalOrderTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    @Test("The result is identical for every permutation of the same entries", arguments: 1...25 as ClosedRange<UInt64>)
    func orderIsAFunctionOfTheSet(seed: UInt64) throws {
        let entries = try concurrentHistory(seed: seed)
        let reference = CausalOrder.sorted(entries).map(\.hash)

        var generator = SeededGenerator(seed: seed)
        for permutation in 0..<8 {
            let shuffled = entries.shuffled(using: &generator)
            #expect(
                CausalOrder.sorted(shuffled).map(\.hash) == reference,
                "seed \(seed): permutation \(permutation) produced a different order")
        }
    }

    @Test("Entries sharing a wall time are separated by their hash, not by arrival")
    func hashBreaksTies() throws {
        var alice = Author()
        var bob = Author()

        let one = try alice.post("same moment", at: start)
        let two = try bob.post("same moment", at: start)

        let expected =
            one.hash.rawValue.lexicographicallyPrecedes(two.hash.rawValue)
            ? [one.hash, two.hash] : [two.hash, one.hash]

        #expect(CausalOrder.sorted([one, two]).map(\.hash) == expected)
        #expect(CausalOrder.sorted([two, one]).map(\.hash) == expected)
    }

    @Test("An entry always follows the one it replied to, however late it looks by the clock")
    func causalityBeatsWallTime() throws {
        var alice = Author()
        var bob = Author()

        let question = try alice.post("blimp or zeppelin", at: start)

        var seen = VectorClock()
        seen.observe(question.feedKey, seq: question.seq)
        let reply = try bob.post("neither, and both", clock: seen, at: start.addingTimeInterval(-3_600))

        #expect(CausalOrder.sorted([reply, question]).map(\.hash) == [question.hash, reply.hash])
    }

    @Test("A feed's own entries never come out of sequence")
    func feedsStayInOrder() throws {
        var alice = Author()
        let first = try alice.post("one", at: start.addingTimeInterval(100))
        let second = try alice.post("two", at: start)
        let third = try alice.post("three", at: start.addingTimeInterval(50))

        #expect(
            CausalOrder.sorted([third, first, second]).map(\.hash)
                == [first.hash, second.hash, third.hash])
    }

    @Test("A gap in a feed does not stall the entries after it")
    func gapsDoNotStall() throws {
        var alice = Author()
        let first = try alice.post("one", at: start)
        _ = try alice.post("missing", at: start.addingTimeInterval(1))
        let third = try alice.post("three", at: start.addingTimeInterval(2))

        #expect(CausalOrder.sorted([third, first]).map(\.hash) == [first.hash, third.hash])
    }

    @Test("Sorting is total: nothing is dropped and nothing is duplicated")
    func totality() throws {
        let entries = try concurrentHistory(seed: 99)
        let sorted = CausalOrder.sorted(entries)

        #expect(sorted.count == entries.count)
        #expect(Set(sorted.map(\.hash)) == Set(entries.map(\.hash)))
    }

    @Test("An entry whose clock claims an impossible dependency still comes out, rather than hanging")
    func survivesADishonestClock() throws {
        var alice = Author()
        var bob = Author()
        let real = try alice.post("real", at: start)

        var impossible = VectorClock()
        impossible.observe(alice.feedKey, seq: 500)
        let liar = try bob.post("claims to have seen the future", clock: impossible, at: start)

        let sorted = CausalOrder.sorted([liar, real])

        #expect(sorted.count == 2)
        #expect(sorted.map(\.hash) == [real.hash, liar.hash])
    }

    @Test("Empty and single-entry inputs are handled without special-casing at the call site")
    func degenerateInputs() throws {
        var alice = Author()
        let only = try alice.post("alone", at: start)

        #expect(CausalOrder.sorted([]).isEmpty)
        #expect(CausalOrder.sorted([only]).map(\.hash) == [only.hash])
    }

    @Test(
        "The order is the one the full set of dependencies gives, forks and gaps included",
        arguments: 1...30 as ClosedRange<UInt64>)
    func matchesTheFullDependencyOrder(seed: UInt64) throws {
        let entries = try forkedHistoryWithGaps(seed: seed, steps: 60)
        #expect(CausalOrder.sorted(entries).map(\.hash) == Self.fullDependencyOrder(entries).map(\.hash))
    }

    @Test("Sorting a thousand entries takes a fraction of a second")
    func sortingIsNotQuadratic() throws {
        let entries = try forkedHistoryWithGaps(seed: 7, steps: 1_000)
        let took = (0..<3).map { _ in
            let started = Date()
            _ = CausalOrder.sorted(entries)
            return Date().timeIntervalSince(started)
        }.min() ?? 0

        #expect(
            took < 0.25,
            """
            Sorting \(entries.count) entries took \(Int(took * 1_000))ms. The projection sorts the \
            whole log every time it is rebuilt, which is after every send and every sync.
            """)
    }

    private func forkedHistoryWithGaps(seed: UInt64, steps: Int) throws -> [Entry] {
        var generator = SeededGenerator(seed: seed)
        var members = [Author(), Author(), Author(), Author()]
        var views = [VectorClock](repeating: VectorClock(), count: members.count)
        var entries: [Entry] = []

        for step in 0..<steps {
            let index = Int.random(in: 0..<members.count, using: &generator)
            for _ in 0..<Int.random(in: 0...2, using: &generator) {
                if let heard = entries.randomElement(using: &generator) {
                    views[index].observe(heard.feedKey, seq: heard.seq)
                }
            }
            let at = start.addingTimeInterval(Double(step / 3))
            if step % 17 == 5 {
                var twin = members[index]
                entries.append(try twin.post("fork \(step)", clock: views[index], at: at))
            }
            let entry = try members[index].post("entry \(step)", clock: views[index], at: at)
            views[index].observe(entry.feedKey, seq: entry.seq)
            entries.append(entry)
        }
        return entries.enumerated().filter { $0.offset % 11 != 3 }.map(\.element)
    }

    private static func fullDependencyOrder(_ entries: [Entry]) -> [Entry] {
        let byHash = Dictionary(entries.map { ($0.hash, $0) }, uniquingKeysWith: { first, _ in first })
        var byFeed: [FeedKey: [(seq: UInt64, hash: EntryHash)]] = [:]
        for entry in byHash.values { byFeed[entry.feedKey, default: []].append((entry.seq, entry.hash)) }
        func upTo(_ feed: FeedKey, _ seq: UInt64) -> [EntryHash] {
            (byFeed[feed] ?? []).filter { $0.seq <= seq }.map(\.hash)
        }
        let precedes = { (left: Entry, right: Entry) -> Bool in
            if left.wallTime != right.wallTime { return left.wallTime < right.wallTime }
            return left.hash.rawValue.lexicographicallyPrecedes(right.hash.rawValue)
        }

        var dependencies: [EntryHash: Set<EntryHash>] = [:]
        var dependents: [EntryHash: [EntryHash]] = [:]
        for entry in byHash.values {
            var required = Set(entry.seq > Entry.firstSequence ? upTo(entry.feedKey, entry.seq - 1) : [])
            for key in entry.clock.keys where key != entry.feedKey { required.formUnion(upTo(key, entry.clock[key])) }
            required.remove(entry.hash)
            dependencies[entry.hash] = required
            for requirement in required { dependents[requirement, default: []].append(entry.hash) }
        }

        var remaining = Set(byHash.keys)
        var ready = remaining.filter { dependencies[$0]?.isEmpty ?? true }
        var ordered: [Entry] = []
        while let next = ready.map({ byHash[$0]! }).min(by: precedes) {
            ready.remove(next.hash)
            remaining.remove(next.hash)
            ordered.append(next)
            for dependent in dependents[next.hash] ?? [] {
                dependencies[dependent]?.remove(next.hash)
                if dependencies[dependent]?.isEmpty == true, remaining.contains(dependent) { ready.insert(dependent) }
            }
        }
        return ordered + remaining.map { byHash[$0]! }.sorted(by: precedes)
    }

    private func concurrentHistory(seed: UInt64) throws -> [Entry] {
        var generator = SeededGenerator(seed: seed)
        var members = [Author(), Author(), Author()]
        var views = [VectorClock](repeating: VectorClock(), count: members.count)
        var entries: [Entry] = []

        for step in 0..<24 {
            let index = Int.random(in: 0..<members.count, using: &generator)
            if let heard = entries.randomElement(using: &generator) {
                views[index].observe(heard.feedKey, seq: heard.seq)
            }
            let entry = try members[index].post(
                "entry \(step)", clock: views[index], at: start.addingTimeInterval(Double(step / 4)))
            views[index].observe(entry.feedKey, seq: entry.seq)
            entries.append(entry)
        }
        return entries
    }
}
