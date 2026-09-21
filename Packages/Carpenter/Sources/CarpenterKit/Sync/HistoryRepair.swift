import Foundation

public struct SequenceSpan: Hashable, Sendable, Codable {
    public let lower: UInt64
    public let upper: UInt64

    public init(_ lower: UInt64, _ upper: UInt64) {
        precondition(lower <= upper, "a span runs upward")
        self.lower = lower
        self.upper = upper
    }

    public var count: UInt64 { upper - lower + 1 }
    public var sequences: ClosedRange<UInt64> { lower...upper }
    public func contains(_ seq: UInt64) -> Bool { sequences.contains(seq) }
}

public struct FeedGap: Hashable, Sendable, Codable {
    public let feed: FeedKey
    public let spans: [SequenceSpan]

    public init(feed: FeedKey, spans: [SequenceSpan]) {
        self.feed = feed
        self.spans = spans
    }

    public var count: UInt64 { spans.reduce(0) { $0 + $1.count } }
    public func contains(_ seq: UInt64) -> Bool { spans.contains { $0.contains(seq) } }

    static func spans(of sequences: [UInt64]) -> [SequenceSpan] {
        var spans: [SequenceSpan] = []
        var run: (from: UInt64, to: UInt64)?
        for seq in sequences {
            if let current = run, seq == current.to + 1 {
                run = (current.from, seq)
            } else {
                if let current = run { spans.append(SequenceSpan(current.from, current.to)) }
                run = (seq, seq)
            }
        }
        if let current = run { spans.append(SequenceSpan(current.from, current.to)) }
        return spans
    }
}

extension [FeedGap] {
    public var total: Int { reduce(0) { $0 + Int($1.count) } }

    public func contains(_ feed: FeedKey, _ seq: UInt64) -> Bool {
        contains { $0.feed == feed && $0.contains(seq) }
    }

    public func stillMissing(of original: [FeedGap]) -> Int { intersecting(original).total }

    public func intersecting(_ original: [FeedGap]) -> [FeedGap] {
        var result: [FeedGap] = []
        for gap in original {
            var still: [UInt64] = []
            for span in gap.spans {
                for seq in span.sequences where contains(gap.feed, seq) { still.append(seq) }
            }
            if !still.isEmpty {
                result.append(FeedGap(feed: gap.feed, spans: FeedGap.spans(of: still)))
            }
        }
        return result
    }

    public mutating func insert(_ feed: FeedKey, _ seq: UInt64) {
        if let index = firstIndex(where: { $0.feed == feed }) {
            var sequences: [UInt64] = []
            for span in self[index].spans { sequences.append(contentsOf: span.sequences) }
            guard !sequences.contains(seq) else { return }
            sequences.append(seq)
            sequences.sort()
            self[index] = FeedGap(feed: feed, spans: FeedGap.spans(of: sequences))
        } else {
            append(FeedGap(feed: feed, spans: [SequenceSpan(seq, seq)]))
        }
    }

    public func subtracting(_ other: [FeedGap]) -> [FeedGap] {
        guard !other.isEmpty else { return self }
        var result: [FeedGap] = []
        for gap in self {
            var held: [UInt64] = []
            for span in gap.spans { held.append(contentsOf: span.sequences) }
            let remaining = held.filter { !other.contains(gap.feed, $0) }
            if !remaining.isEmpty {
                result.append(FeedGap(feed: gap.feed, spans: FeedGap.spans(of: remaining)))
            }
        }
        return result
    }
}

public struct RepairID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum RepairReason: String, Hashable, Sendable, Codable {
    case gap
    case recovery
}

public struct RepairRequest: Hashable, Sendable, Codable {
    public let id: RepairID
    public let authors: [ParticipantID]
    public let heads: VectorClock
    public let gaps: [FeedGap]
    public let room: ConversationID?
    public let wallOf: ParticipantID?
    public let reason: RepairReason

    public init(
        id: RepairID = RepairID(), authors: [ParticipantID], heads: VectorClock, gaps: [FeedGap],
        room: ConversationID? = nil, wallOf: ParticipantID? = nil, reason: RepairReason = .gap
    ) {
        self.id = id
        self.authors = authors
        self.heads = heads
        self.gaps = gaps
        self.room = room
        self.wallOf = wallOf
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case id, authors, heads, gaps, room, wallOf, reason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(RepairID.self, forKey: .id)
        authors = try container.decodeIfPresent([ParticipantID].self, forKey: .authors) ?? []
        heads = try container.decodeIfPresent(VectorClock.self, forKey: .heads) ?? VectorClock()
        gaps = try container.decodeIfPresent([FeedGap].self, forKey: .gaps) ?? []
        room = try container.decodeIfPresent(ConversationID.self, forKey: .room)
        wallOf = try container.decodeIfPresent(ParticipantID.self, forKey: .wallOf)
        reason = try container.decodeIfPresent(RepairReason.self, forKey: .reason) ?? .gap
    }

    public var namedCount: Int { gaps.total }
}

public struct RepairAnswer: Hashable, Sendable, Codable {
    public let request: RepairID
    public let unheld: [FeedGap]
    public let elsewhere: [FeedGap]
    public let heads: VectorClock

    public init(
        request: RepairID, unheld: [FeedGap], elsewhere: [FeedGap] = [], heads: VectorClock
    ) {
        self.request = request
        self.unheld = unheld
        self.elsewhere = elsewhere
        self.heads = heads
    }

    private enum CodingKeys: String, CodingKey { case request, unheld, elsewhere, heads }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = try container.decode(RepairID.self, forKey: .request)
        unheld = try container.decodeIfPresent([FeedGap].self, forKey: .unheld) ?? []
        elsewhere = try container.decodeIfPresent([FeedGap].self, forKey: .elsewhere) ?? []
        heads = try container.decodeIfPresent(VectorClock.self, forKey: .heads) ?? VectorClock()
    }
}

extension Replica {
    public func fill(
        _ request: RepairRequest
    ) -> (entries: [Entry], unheld: [FeedGap], elsewhere: [FeedGap]) {
        var found: [Entry] = []
        var seen: Set<EntryHash> = []
        func take(_ entries: [Entry]) {
            for entry in entries where seen.insert(entry.hash).inserted { found.append(entry) }
        }

        let authors = Set(request.authors)
        let wantsWall = request.wallOf
        func wasAskedFor(_ entry: Entry) -> Bool {
            if let room = request.room { return entry.room == room }
            if let wantsWall {
                if entry.room == nil { return entry.author == wantsWall }
                return entry.room == ConversationID.outpost(of: wantsWall)
            }
            return authors.contains(entry.author)
        }

        var unheld: [FeedGap] = []
        var elsewhere: [FeedGap] = []
        for gap in request.gaps {
            var lacking: [UInt64] = []
            var apart: [UInt64] = []
            for span in gap.spans {
                for seq in span.sequences {
                    let held = entries(in: gap.feed, at: seq)
                    if held.isEmpty {
                        lacking.append(seq)
                        continue
                    }
                    let asked = held.filter(wasAskedFor)
                    if asked.isEmpty { apart.append(seq) } else { take(asked) }
                }
            }
            if !lacking.isEmpty {
                unheld.append(FeedGap(feed: gap.feed, spans: FeedGap.spans(of: lacking)))
            }
            if !apart.isEmpty {
                elsewhere.append(FeedGap(feed: gap.feed, spans: FeedGap.spans(of: apart)))
            }
        }

        for feed in heldFeeds {
            guard let top = highestSequence(in: feed) else { continue }
            let from = request.heads[feed] + 1
            guard from <= top else { continue }
            for seq in from...top { take(entries(in: feed, at: seq).filter(wasAskedFor)) }
        }

        found.sort {
            if $0.feedKey != $1.feedKey {
                return $0.feedKey.canonicalBytes.lexicographicallyPrecedes($1.feedKey.canonicalBytes)
            }
            return $0.seq < $1.seq
        }
        return (found, unheld, elsewhere)
    }

    public func heads(inScopeOf request: RepairRequest) -> VectorClock {
        heads(of: Set(request.authors), inRoom: request.room, onWallOf: request.wallOf)
    }

    public func heads(
        of authors: Set<ParticipantID>, inRoom room: ConversationID?, onWallOf wantsWall: ParticipantID?
    ) -> VectorClock {
        var clock = VectorClock()
        for entry in allEntries where authors.contains(entry.feedKey.author) {
            let asked: Bool
            if let room {
                asked = entry.room == room
            } else if let wantsWall {
                asked =
                    entry.room == nil
                    ? entry.author == wantsWall : entry.room == ConversationID.outpost(of: wantsWall)
            } else {
                asked = true
            }
            guard asked, entry.seq > clock[entry.feedKey] else { continue }
            clock.observe(entry.feedKey, seq: entry.seq)
        }
        return clock
    }
}

public struct HeldRestore: Hashable, Sendable, Identifiable {
    public let request: RepairID
    public let person: ParticipantID
    public let personName: String
    public let room: ConversationID?
    public let roomName: String
    public let phrase: String?
    public let askedAt: Date

    public var id: RepairID { request }

    public init(
        request: RepairID, person: ParticipantID, personName: String, room: ConversationID?,
        roomName: String, phrase: String?, askedAt: Date
    ) {
        self.request = request
        self.person = person
        self.personName = personName
        self.room = room
        self.roomName = roomName
        self.phrase = phrase
        self.askedAt = askedAt
    }
}
