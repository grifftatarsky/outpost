import Foundation

public enum CausalOrder {
    public static func sorted(_ entries: [Entry]) -> [Entry] {
        guard entries.count > 1 else { return entries }

        var seen: Set<EntryHash> = []
        let unique = entries.filter { seen.insert($0.hash).inserted }
        let index = FeedIndex(unique)

        var waitingOn = [Int](repeating: 0, count: unique.count)
        var dependents = [[Int]](repeating: [], count: unique.count)
        for (position, entry) in unique.enumerated() {
            let required = index.dependencies(of: entry)
            waitingOn[position] = required.count
            for requirement in required { dependents[requirement].append(position) }
        }

        var ready = ReadyEntries(unique)
        for position in unique.indices where waitingOn[position] == 0 { ready.push(position) }

        var placed = [Bool](repeating: false, count: unique.count)
        var ordered: [Entry] = []
        ordered.reserveCapacity(unique.count)
        while let next = ready.pop() {
            placed[next] = true
            ordered.append(unique[next])
            for dependent in dependents[next] {
                waitingOn[dependent] -= 1
                if waitingOn[dependent] == 0 { ready.push(dependent) }
            }
        }

        if ordered.count < unique.count {
            ordered.append(contentsOf: unique.indices.filter { !placed[$0] }.map { unique[$0] }.sorted(by: precedes))
        }
        return ordered
    }

    fileprivate static func precedes(_ left: Entry, _ right: Entry) -> Bool {
        if left.wallTime != right.wallTime { return left.wallTime < right.wallTime }
        return left.hash.rawValue.lexicographicallyPrecedes(right.hash.rawValue)
    }
}

private struct FeedIndex {
    private var byFeed: [FeedKey: [(seq: UInt64, position: Int)]] = [:]

    init(_ entries: [Entry]) {
        for (position, entry) in entries.enumerated() {
            byFeed[entry.feedKey, default: []].append((entry.seq, position))
        }
        for key in byFeed.keys {
            byFeed[key]?.sort { $0.seq < $1.seq }
        }
    }

    func dependencies(of entry: Entry) -> [Int] {
        var required: [Int] = []

        if entry.seq > Entry.firstSequence {
            appendLatest(in: entry.feedKey, atMost: entry.seq - 1, to: &required)
        }

        let own = entry.feedKey
        for (key, seq) in entry.clock.positions where key != own {
            appendLatest(in: key, atMost: seq, to: &required)
        }

        return required
    }

    private func appendLatest(in feed: FeedKey, atMost seq: UInt64, to required: inout [Int]) {
        guard let entries = byFeed[feed] else { return }
        var low = 0
        var high = entries.count
        while low < high {
            let middle = (low + high) / 2
            if entries[middle].seq <= seq { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return }
        let top = entries[low - 1].seq
        var at = low - 1
        while at >= 0, entries[at].seq == top {
            required.append(entries[at].position)
            at -= 1
        }
    }
}

private struct ReadyEntries {
    private let entries: [Entry]
    private var heap: [Int] = []

    init(_ entries: [Entry]) {
        self.entries = entries
    }

    mutating func push(_ position: Int) {
        heap.append(position)
        var child = heap.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard comesFirst(heap[child], heap[parent]) else { break }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Int? {
        guard let first = heap.first else { return nil }
        let last = heap.removeLast()
        guard !heap.isEmpty else { return first }
        heap[0] = last
        var parent = 0
        while true {
            let left = 2 * parent + 1
            let right = left + 1
            var smallest = parent
            if left < heap.count, comesFirst(heap[left], heap[smallest]) { smallest = left }
            if right < heap.count, comesFirst(heap[right], heap[smallest]) { smallest = right }
            guard smallest != parent else { break }
            heap.swapAt(parent, smallest)
            parent = smallest
        }
        return first
    }

    private func comesFirst(_ left: Int, _ right: Int) -> Bool {
        CausalOrder.precedes(entries[left], entries[right])
    }
}
