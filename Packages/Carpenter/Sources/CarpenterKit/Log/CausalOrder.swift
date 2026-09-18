import Foundation

public enum CausalOrder {
    public static func sorted(_ entries: [Entry]) -> [Entry] {
        guard entries.count > 1 else { return entries }

        let byHash = Dictionary(entries.map { ($0.hash, $0) }, uniquingKeysWith: { first, _ in first })
        let index = FeedIndex(entries: byHash.values)

        var dependencies: [EntryHash: Set<EntryHash>] = [:]
        var dependents: [EntryHash: [EntryHash]] = [:]

        for entry in byHash.values {
            let required = index.dependencies(of: entry).subtracting([entry.hash])
            dependencies[entry.hash] = required
            for requirement in required {
                dependents[requirement, default: []].append(entry.hash)
            }
        }

        var remaining = Set(byHash.keys)
        var ready = remaining.filter { dependencies[$0]?.isEmpty ?? true }
        var ordered: [Entry] = []
        ordered.reserveCapacity(byHash.count)

        while !ready.isEmpty {
            let next = ready.map { byHash[$0]! }.min(by: precedes)!
            ready.remove(next.hash)
            remaining.remove(next.hash)
            ordered.append(next)

            for dependent in dependents[next.hash] ?? [] {
                dependencies[dependent]?.remove(next.hash)
                if dependencies[dependent]?.isEmpty == true, remaining.contains(dependent) {
                    ready.insert(dependent)
                }
            }
        }

        if !remaining.isEmpty {
            ordered.append(contentsOf: remaining.map { byHash[$0]! }.sorted(by: precedes))
        }

        return ordered
    }

    private static func precedes(_ left: Entry, _ right: Entry) -> Bool {
        if left.wallTime != right.wallTime { return left.wallTime < right.wallTime }
        return left.hash.rawValue.lexicographicallyPrecedes(right.hash.rawValue)
    }
}

private struct FeedIndex {
    private var byFeed: [FeedKey: [(seq: UInt64, hash: EntryHash)]] = [:]

    init(entries: some Collection<Entry>) {
        for entry in entries {
            byFeed[entry.feedKey, default: []].append((entry.seq, entry.hash))
        }
        for key in byFeed.keys {
            byFeed[key]?.sort { $0.seq < $1.seq }
        }
    }

    func dependencies(of entry: Entry) -> Set<EntryHash> {
        var required: Set<EntryHash> = []

        if entry.seq > Entry.firstSequence {
            required.formUnion(hashes(in: entry.feedKey, upTo: entry.seq - 1))
        }

        for key in entry.clock.keys where key != entry.feedKey {
            required.formUnion(hashes(in: key, upTo: entry.clock[key]))
        }

        return required
    }

    private func hashes(in feed: FeedKey, upTo seq: UInt64) -> [EntryHash] {
        guard let entries = byFeed[feed] else { return [] }
        return entries.prefix { $0.seq <= seq }.map(\.hash)
    }
}
