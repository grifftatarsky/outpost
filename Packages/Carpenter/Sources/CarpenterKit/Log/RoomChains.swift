import Foundation

public struct RoomChains: Sendable {
    struct Link: Sendable {
        let feed: FeedKey
        let room: RoomID
        let previous: EntryHash?
    }

    private var links: [EntryHash: Link] = [:]

    public init(_ entries: [Entry] = []) {
        for entry in entries {
            guard let room = entry.room, let link = entry.roomLink else { continue }
            links[entry.hash] = Link(feed: entry.feedKey, room: room, previous: link.previous)
        }
    }

    func line(through heads: [EntryHash]) -> Set<EntryHash> {
        var line: Set<EntryHash> = []
        for head in heads {
            guard let start = links[head] else { continue }
            var current: EntryHash? = head
            while let hash = current, let link = links[hash], link.feed == start.feed, link.room == start.room,
                line.insert(hash).inserted
            {
                current = link.previous
            }
        }
        return line
    }
}
