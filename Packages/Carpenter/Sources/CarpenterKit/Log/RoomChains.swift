import Foundation

public struct RoomChains: Sendable {
    struct Link: Sendable {
        let feed: FeedKey
        let room: RoomID
        let seq: UInt64
        let previous: EntryHash?
        let isChained: Bool
    }

    struct Line {
        var onChain: Set<EntryHash> = []
        var unchainedUpTo: [FeedKey: UInt64] = [:]
    }

    private var links: [EntryHash: Link] = [:]

    public init(_ entries: [Entry] = []) {
        for entry in entries {
            guard let room = entry.room else { continue }
            links[entry.hash] = Link(
                feed: entry.feedKey, room: room, seq: entry.seq, previous: entry.roomLink?.previous,
                isChained: entry.roomLink != nil)
        }
    }

    func isChained(_ entry: EntryHash) -> Bool { links[entry]?.isChained ?? false }

    func line(through heads: [EntryHash]) -> Line {
        var line = Line()
        for head in heads {
            guard let start = links[head] else { continue }
            var current: EntryHash? = head
            while let hash = current, let link = links[hash], link.feed == start.feed, link.room == start.room,
                !line.onChain.contains(hash)
            {
                line.onChain.insert(hash)
                guard link.isChained else {
                    line.unchainedUpTo[link.feed] = max(line.unchainedUpTo[link.feed] ?? 0, link.seq)
                    break
                }
                current = link.previous
            }
        }
        return line
    }
}
