import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Convergence")
struct ConvergenceTests {
    private static let seeds: [UInt64] = Array(1...20)

    @Test("Any interleaving of concurrent history converges", arguments: seeds)
    func converges(seed: UInt64) throws {
        let history = try History(seed: seed, members: 4, operations: 60)

        let renderings = try (0..<4).map { replicaIndex in
            var generator = SeededGenerator(seed: seed &* 31 &+ UInt64(replicaIndex))
            var replica = Replica()
            for member in history.members { try replica.meet(member) }

            for entry in history.entries.shuffled(using: &generator) {
                try replica.integrate(entry)
            }

            #expect(!replica.hasDiverged, "seed \(seed): honest authors must not fork")
            return Fold.render(replica.ordered(), using: history.chain)
        }

        let reference = try #require(renderings.first)
        for (index, rendering) in renderings.enumerated().dropFirst() {
            #expect(
                rendering == reference,
                "seed \(seed): replica \(index) disagrees with replica 0")
        }
    }

    @Test("Delivering a history in two halves matches delivering it all at once", arguments: seeds.prefix(15))
    func incrementalDeliveryMatches(seed: UInt64) throws {
        let history = try History(seed: seed, members: 3, operations: 40)
        var generator = SeededGenerator(seed: seed)
        let shuffled = history.entries.shuffled(using: &generator)

        var wholesale = Replica()
        var piecewise = Replica()
        for member in history.members {
            try wholesale.meet(member)
            try piecewise.meet(member)
        }

        for entry in shuffled { try wholesale.integrate(entry) }

        let split = shuffled.count / 2
        for entry in shuffled[split...] { try piecewise.integrate(entry) }
        for entry in shuffled[..<split] { try piecewise.integrate(entry) }

        #expect(Fold.render(piecewise.ordered(), using: history.chain) == Fold.render(wholesale.ordered(), using: history.chain))
    }

    @Test("Redelivering everything a second time changes nothing", arguments: seeds.prefix(10))
    func redeliveryIsIdempotent(seed: UInt64) throws {
        let history = try History(seed: seed, members: 3, operations: 30)

        var replica = Replica()
        for member in history.members { try replica.meet(member) }
        for entry in history.entries { try replica.integrate(entry) }

        let once = Fold.render(replica.ordered(), using: history.chain)

        for entry in history.entries { try replica.integrate(entry) }

        #expect(Fold.render(replica.ordered(), using: history.chain) == once)
        #expect(!replica.hasDiverged)
    }

    @Test("Causal order is respected: an entry never renders before something it had already seen",
          arguments: seeds.prefix(15))
    func respectsCausality(seed: UInt64) throws {
        let history = try History(seed: seed, members: 4, operations: 50)
        let ordered = CausalOrder.sorted(history.entries)

        var emitted: [FeedKey: UInt64] = [:]
        var seen: Set<EntryHash> = []

        for entry in ordered {
            for key in entry.clock.keys where key != entry.feedKey {
                let observed = entry.clock[key]
                let missing = history.entries.contains {
                    $0.feedKey == key && $0.seq <= observed && !seen.contains($0.hash)
                }
                #expect(!missing, "seed \(seed): an entry preceded something its author had seen")
            }
            if let previous = emitted[entry.feedKey] {
                #expect(entry.seq > previous, "seed \(seed): a feed came out of order")
            }
            emitted[entry.feedKey] = entry.seq
            seen.insert(entry.hash)
        }
    }
}

private struct History {
    private(set) var members: [Author] = []
    private(set) var entries: [Entry] = []
    let chain: EpochChain

    init(seed: UInt64, members memberCount: Int, operations: Int) throws {
        var generator = SeededGenerator(seed: seed)
        let start = Date(timeIntervalSince1970: 1_786_635_000)
        let room = ConversationID.room(UUID())
        chain = EpochChain.create(room: room).chain

        members = (0..<memberCount).map { _ in Author(chain: chain) }
        var views = [VectorClock](repeating: VectorClock(), count: memberCount)
        var posts: [Entry] = []

        for step in 0..<operations {
            let index = Int.random(in: 0..<memberCount, using: &generator)
            if !entries.isEmpty, Int.random(in: 0..<3, using: &generator) > 0 {
                let heard = entries.randomElement(using: &generator)!
                views[index].observe(heard.feedKey, seq: heard.seq)
            }

            let wallTime = start.addingTimeInterval(Double(step / 3))
            let payload = try nextPayload(
                posts: posts, author: members[index], using: &generator)

            let entry = try members[index].append(
                payload, clock: views[index], at: wallTime, room: room)

            views[index].observe(entry.feedKey, seq: entry.seq)
            entries.append(entry)
            if payload.type == .post { posts.append(entry) }
        }
    }

    private func nextPayload(
        posts: [Entry], author: Author, using generator: inout SeededGenerator
    ) throws -> Payload {
        let ownPosts = posts.filter { $0.author == author.identity.id }

        switch Int.random(in: 0..<10, using: &generator) {
        case 0..<5:
            return try Payload.post("entry \(Int.random(in: 0..<1_000, using: &generator))")
        case 5..<7 where !ownPosts.isEmpty:
            let target = ownPosts.randomElement(using: &generator)!
            return try Payload.edit(target.hash, to: "edited \(Int.random(in: 0..<1_000, using: &generator))")
        case 7 where !ownPosts.isEmpty:
            return try Payload.tombstone(ownPosts.randomElement(using: &generator)!.hash)
        case 8..<10 where !posts.isEmpty:
            let target = posts.randomElement(using: &generator)!
            let emoji = ["🎈", "🔥", "⚓️", nil][Int.random(in: 0..<4, using: &generator)]
            return try Payload.reaction(target.hash, emoji: emoji)
        default:
            return try Payload.post("entry \(Int.random(in: 0..<1_000, using: &generator))")
        }
    }
}
