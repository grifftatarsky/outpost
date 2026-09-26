import Foundation

public struct SequenceSpan: Hashable, Sendable, Codable {
    public let lower: UInt64
    public let upper: UInt64

    public init(_ lower: UInt64, _ upper: UInt64) {
        precondition(lower <= upper, "a span runs upward")
        self.lower = lower
        self.upper = upper
    }

    public var count: UInt64 {
        guard lower <= upper else { return 0 }
        let (count, overflowed) = (upper - lower).addingReportingOverflow(1)
        return overflowed ? .max : count
    }

    public func contains(_ seq: UInt64) -> Bool { lower <= seq && seq <= upper }
}

extension [SequenceSpan] {
    public var sequenceCount: UInt64 { reduce(0) { $0.addingSaturated($1.count) } }

    public var normalized: [SequenceSpan] {
        var merged: [SequenceSpan] = []
        for span in filter({ $0.lower <= $0.upper }).sorted(by: { $0.lower < $1.lower }) {
            if let last = merged.last, last.upper == .max || span.lower <= last.upper + 1 {
                merged[merged.count - 1] = SequenceSpan(last.lower, Swift.max(last.upper, span.upper))
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    public func intersecting(_ other: [SequenceSpan]) -> [SequenceSpan] {
        let (left, right) = (normalized, other.normalized)
        var result: [SequenceSpan] = []
        var (i, j) = (0, 0)
        while i < left.count, j < right.count {
            let lower = Swift.max(left[i].lower, right[j].lower)
            let upper = Swift.min(left[i].upper, right[j].upper)
            if lower <= upper { result.append(SequenceSpan(lower, upper)) }
            if left[i].upper < right[j].upper { i += 1 } else { j += 1 }
        }
        return result
    }

    public func subtracting(_ other: [SequenceSpan]) -> [SequenceSpan] {
        let removing = other.normalized
        var result: [SequenceSpan] = []
        var first = 0
        for span in normalized {
            while first < removing.count, removing[first].upper < span.lower { first += 1 }
            var lower = span.lower
            var covered = false
            var index = first
            while index < removing.count, removing[index].lower <= span.upper {
                let cut = removing[index]
                if cut.lower > lower { result.append(SequenceSpan(lower, cut.lower - 1)) }
                if cut.upper >= span.upper {
                    covered = true
                    break
                }
                lower = Swift.max(lower, cut.upper + 1)
                index += 1
            }
            if !covered { result.append(SequenceSpan(lower, span.upper)) }
        }
        return result
    }
}

extension UInt64 {
    public func addingSaturated(_ other: UInt64) -> UInt64 {
        let (sum, overflowed) = addingReportingOverflow(other)
        return overflowed ? .max : sum
    }
}

public struct FeedGap: Hashable, Sendable, Codable {
    public let feed: FeedKey
    public let spans: [SequenceSpan]

    public init(feed: FeedKey, spans: [SequenceSpan]) {
        self.feed = feed
        self.spans = spans
    }

    public var count: UInt64 { spans.sequenceCount }
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
    public var total: Int { Int(clamping: reduce(UInt64(0)) { $0.addingSaturated($1.count) }) }

    public func contains(_ feed: FeedKey, _ seq: UInt64) -> Bool {
        contains { $0.feed == feed && $0.contains(seq) }
    }

    public func spans(of feed: FeedKey) -> [SequenceSpan] {
        filter { $0.feed == feed }.flatMap(\.spans)
    }

    public func stillMissing(of original: [FeedGap]) -> Int { intersecting(original).total }

    public func intersecting(_ original: [FeedGap]) -> [FeedGap] {
        original.compactMap { gap in
            let still = gap.spans.intersecting(spans(of: gap.feed))
            return still.isEmpty ? nil : FeedGap(feed: gap.feed, spans: still)
        }
    }

    public mutating func insert(_ feed: FeedKey, _ seq: UInt64) {
        if let index = firstIndex(where: { $0.feed == feed }) {
            guard !self[index].contains(seq) else { return }
            self[index] = FeedGap(feed: feed, spans: (self[index].spans + [SequenceSpan(seq, seq)]).normalized)
        } else {
            append(FeedGap(feed: feed, spans: [SequenceSpan(seq, seq)]))
        }
    }

    public func subtracting(_ other: [FeedGap]) -> [FeedGap] {
        guard !other.isEmpty else { return self }
        return compactMap { gap in
            let remaining = gap.spans.subtracting(other.spans(of: gap.feed))
            return remaining.isEmpty ? nil : FeedGap(feed: gap.feed, spans: remaining)
        }
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
    public let room: RoomID?
    public let wallOf: ParticipantID?
    public let reason: RepairReason

    public init(
        id: RepairID = RepairID(), authors: [ParticipantID], heads: VectorClock, gaps: [FeedGap],
        room: RoomID? = nil, wallOf: ParticipantID? = nil, reason: RepairReason = .gap
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
        room = try container.decodeIfPresent(RoomID.self, forKey: .room)
        wallOf = try container.decodeIfPresent(ParticipantID.self, forKey: .wallOf)
        reason = try container.decodeIfPresent(RepairReason.self, forKey: .reason) ?? .gap
    }

    public var namedCount: Int { gaps.total }
}

public struct RepairAnswer: Hashable, Sendable, Codable {
    public let request: RepairID
    public let unheld: [FeedGap]
    public let heads: VectorClock

    public init(request: RepairID, unheld: [FeedGap], heads: VectorClock) {
        self.request = request
        self.unheld = unheld
        self.heads = heads
    }

    private enum CodingKeys: String, CodingKey { case request, unheld, heads }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = try container.decode(RepairID.self, forKey: .request)
        unheld = try container.decodeIfPresent([FeedGap].self, forKey: .unheld) ?? []
        heads = try container.decodeIfPresent(VectorClock.self, forKey: .heads) ?? VectorClock()
    }
}

extension Replica {
    public func fill(_ request: RepairRequest) -> (entries: [Entry], unheld: [FeedGap]) {
        var found: [Entry] = []
        var seen: Set<EntryHash> = []
        func take(_ entries: [Entry]) {
            for entry in entries where seen.insert(entry.hash).inserted { found.append(entry) }
        }

        var unheld: [FeedGap] = []
        for gap in request.gaps {
            let wanted = gap.spans.normalized
            var holding: [UInt64] = []
            for position in occupied(in: gap.feed, within: wanted) {
                let held = entries(in: gap.feed, at: position)
                guard !held.isEmpty else { continue }
                take(held)
                holding.append(position)
            }
            let lacking = wanted.subtracting(FeedGap.spans(of: holding))
            if !lacking.isEmpty {
                unheld.append(FeedGap(feed: gap.feed, spans: lacking))
            }
        }

        let authors = Set(request.authors)
        let wantsWall = request.wallOf
        for feed in heldFeeds
        where authors.contains(feed.author) || request.room != nil || wantsWall != nil {
            let whole = authors.contains(feed.author)
            take(
                entries(in: feed, after: request.heads[feed]).filter { entry in
                    if whole { return true }
                    if let room = request.room, entry.room == room { return true }
                    guard let wantsWall else { return false }
                    if entry.room == nil { return entry.author == wantsWall }
                    return entry.room == RoomID.outpost(of: wantsWall)
                })
        }

        found.sort {
            if $0.feedKey != $1.feedKey {
                return $0.feedKey.canonicalBytes.lexicographicallyPrecedes($1.feedKey.canonicalBytes)
            }
            return $0.seq < $1.seq
        }
        return (found, unheld)
    }
}

public struct HeldRestore: Hashable, Sendable, Identifiable {
    public let request: RepairID
    public let person: ParticipantID
    public let personName: String
    public let room: RoomID?
    public let roomName: String
    public let phrase: String?
    public let askedAt: Date

    public var id: RepairID { request }

    public init(
        request: RepairID, person: ParticipantID, personName: String, room: RoomID?,
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
