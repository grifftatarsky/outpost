import Foundation

public struct Fork: Hashable, Sendable {
    public let feed: FeedKey
    public let seq: UInt64
    public let hashes: Set<EntryHash>

    public init(feed: FeedKey, seq: UInt64, hashes: Set<EntryHash>) {
        self.feed = feed
        self.seq = seq
        self.hashes = hashes
    }
}

public enum IntegrationResult: Hashable, Sendable {
    case accepted
    case alreadyPresent
    case forked(Fork)
}

public enum LogError: Error, Hashable, Sendable {
    case unknownParticipant
    case unauthorizedDevice
    case badSignature
    case brokenLink
}

public struct SpentEntry: Hashable, Sendable, Codable {
    public let feed: FeedKey
    public let seq: UInt64
    public let hash: EntryHash
    public let room: RoomID?

    public init(feed: FeedKey, seq: UInt64, hash: EntryHash, room: RoomID?) {
        self.feed = feed
        self.seq = seq
        self.hash = hash
        self.room = room
    }

    public init(_ entry: Entry) {
        self.init(feed: entry.feedKey, seq: entry.seq, hash: entry.hash, room: entry.room)
    }

    public var link: EntryLink { EntryLink(seq: seq, hash: hash) }
}

public struct Replica: Sendable {
    private var registries: [ParticipantID: DeviceRegistry] = [:]
    private var feeds: [FeedKey: [UInt64: [EntryHash: Entry]]] = [:]
    private var spent: [FeedKey: [UInt64: SpentEntry]] = [:]

    public private(set) var closedRooms: Set<RoomID> = []

    public private(set) var forks: [Fork] = []

    private var contiguous: [FeedKey: UInt64] = [:]
    private var scattered: [FeedKey: Set<UInt64>] = [:]
    private var highest: [FeedKey: UInt64] = [:]

    public private(set) var claimed = VectorClock()

    public init() {}

    public var entryCount: Int {
        feeds.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
    }

    public var allEntries: [Entry] {
        feeds.values.flatMap { $0.values.flatMap(\.values) }
    }

    public var hasDiverged: Bool { !forks.isEmpty }

    public mutating func introduce(_ identity: IdentityPublicKeys) {
        registries[identity.participantID] = registries[identity.participantID]
            ?? DeviceRegistry(identity: identity)
    }

    public mutating func admit(_ certificate: DeviceCertificate) throws {
        guard var registry = registries[certificate.participant] else {
            throw LogError.unknownParticipant
        }
        try registry.admit(certificate)
        registries[certificate.participant] = registry
    }

    public mutating func revoke(_ revocation: DeviceRevocation) throws {
        guard var registry = registries[revocation.participant] else {
            throw LogError.unknownParticipant
        }
        try registry.revoke(revocation)
        registries[revocation.participant] = registry
    }

    public var knownParticipants: Set<ParticipantID> { Set(registries.keys) }

    public func registry(for participant: ParticipantID) -> DeviceRegistry? {
        registries[participant]
    }

    @discardableResult
    public mutating func integrate(_ entry: Entry) throws -> IntegrationResult {
        guard let registry = registries[entry.author] else { throw LogError.unknownParticipant }
        guard registry.isAuthorized(entry.device, at: entry.wallTime),
            let deviceKey = registry.signingKey(for: entry.device)
        else {
            throw LogError.unauthorizedDevice
        }
        guard try entry.hasValidSignature(from: deviceKey) else { throw LogError.badSignature }

        if spent[entry.feedKey]?[entry.seq] != nil { return .alreadyPresent }

        let existingAtSeq = feeds[entry.feedKey]?[entry.seq] ?? [:]
        if existingAtSeq[entry.hash] != nil { return .alreadyPresent }

        try validateLink(of: entry)

        if let room = entry.room, closedRooms.contains(room) {
            if existingAtSeq.isEmpty { spend(SpentEntry(entry)) }
            return .alreadyPresent
        }

        feeds[entry.feedKey, default: [:]][entry.seq, default: [:]][entry.hash] = entry
        claimed = claimed.merging(entry.clock)
        if existingAtSeq.isEmpty { occupy(entry.seq, in: entry.feedKey) }

        guard !existingAtSeq.isEmpty else { return .accepted }

        let fork = Fork(
            feed: entry.feedKey,
            seq: entry.seq,
            hashes: Set(existingAtSeq.keys).union([entry.hash])
        )
        forks.removeAll { $0.feed == fork.feed && $0.seq == fork.seq }
        forks.append(fork)
        return .forked(fork)
    }

    private mutating func occupy(_ seq: UInt64, in feed: FeedKey) {
        highest[feed] = Swift.max(highest[feed] ?? 0, seq)

        let run = contiguous[feed] ?? 0
        guard seq > run else { return }
        guard seq == run + 1 else {
            scattered[feed, default: []].insert(seq)
            return
        }

        var reached = seq
        if var waiting = scattered[feed] {
            while waiting.remove(reached + 1) != nil { reached += 1 }
            if waiting.isEmpty { scattered[feed] = nil } else { scattered[feed] = waiting }
        }
        contiguous[feed] = reached
    }

    // MARK: What was taken out on purpose

    public var spentEntries: [SpentEntry] {
        spent.values.flatMap(\.values).sorted {
            $0.feed == $1.feed
                ? $0.seq < $1.seq
                : $0.feed.canonicalBytes.lexicographicallyPrecedes($1.feed.canonicalBytes)
        }
    }

    public func spentLink(atTopOf feed: FeedKey) -> EntryLink? {
        guard let top = highest[feed] else { return nil }
        return spent[feed]?[top]?.link
    }

    public mutating func restore(spent entries: [SpentEntry], closing rooms: Set<RoomID>) {
        closedRooms.formUnion(rooms)
        for entry in entries where feeds[entry.feed]?[entry.seq] == nil { spend(entry) }
    }

    @discardableResult
    public mutating func close(_ room: RoomID) -> [Entry] {
        closedRooms.insert(room)
        var taken: [Entry] = []
        for (feed, bySeq) in feeds {
            var kept = bySeq
            for (seq, atSeq) in bySeq {
                let inRoom = atSeq.values.filter { $0.room == room }
                guard !inRoom.isEmpty else { continue }
                taken.append(contentsOf: inRoom)
                let remaining = atSeq.filter { $0.value.room != room }
                if remaining.isEmpty {
                    kept[seq] = nil
                    let first = inRoom.min {
                        $0.hash.rawValue.lexicographicallyPrecedes($1.hash.rawValue)
                    }
                    if let first { spent[feed, default: [:]][seq] = SpentEntry(first) }
                } else {
                    kept[seq] = remaining
                }
            }
            feeds[feed] = kept.isEmpty ? nil : kept
        }
        forks.removeAll { fork in (feeds[fork.feed]?[fork.seq]?.count ?? 0) < 2 }
        return taken
    }

    public mutating func reopen(_ room: RoomID) {
        closedRooms.remove(room)
        var touched: Set<FeedKey> = []
        for (feed, bySeq) in spent {
            let kept = bySeq.filter { $0.value.room != room }
            guard kept.count != bySeq.count else { continue }
            spent[feed] = kept.isEmpty ? nil : kept
            touched.insert(feed)
        }
        for feed in touched { reindex(feed) }
    }

    private mutating func spend(_ entry: SpentEntry) {
        spent[entry.feed, default: [:]][entry.seq] = entry
        occupy(entry.seq, in: entry.feed)
    }

    private mutating func reindex(_ feed: FeedKey) {
        let held = Set(feeds[feed]?.keys.map { $0 } ?? []).union(spent[feed]?.keys.map { $0 } ?? [])
        highest[feed] = held.max()
        var run: UInt64 = 0
        while held.contains(run + 1) { run += 1 }
        contiguous[feed] = run == 0 ? nil : run
        let beyond = held.filter { $0 > run }
        scattered[feed] = beyond.isEmpty ? nil : beyond
    }

    public func refusesForever(_ entry: Entry) -> Bool {
        guard let registry = registries[entry.author] else { return false }
        guard registry.standing(of: entry.device) != nil else { return false }
        return !registry.isAuthorized(entry.device, at: entry.wallTime)
    }

    private func validateLink(of entry: Entry) throws {
        guard entry.seq > Entry.firstSequence else {
            guard entry.seq == Entry.firstSequence else { throw LogError.brokenLink }
            guard entry.previous == nil else { throw LogError.brokenLink }
            return
        }
        guard entry.previous != nil else { throw LogError.brokenLink }

        let predecessors = feeds[entry.feedKey]?[entry.seq - 1] ?? [:]
        guard !predecessors.isEmpty else { return }
        guard let claimed = entry.previous, predecessors[claimed] != nil else {
            throw LogError.brokenLink
        }
    }

    public func entries(in room: RoomID?) -> [Entry] {
        CausalOrder.sorted(allEntries.filter { $0.room == room })
    }

    public func ordered() -> [Entry] {
        CausalOrder.sorted(allEntries)
    }

    public var frontier: VectorClock {
        var clock = VectorClock()
        for (key, top) in highest { clock.observe(key, seq: top) }
        return clock
    }

    public func head(of feed: FeedKey) -> Entry? {
        guard let bySeq = feeds[feed], let highest = bySeq.keys.max() else { return nil }
        return bySeq[highest]?.values.min { $0.hash.rawValue.lexicographicallyPrecedes($1.hash.rawValue) }
    }

    // MARK: What is missing

    public var heldFeeds: Set<FeedKey> { Set(feeds.keys) }

    public func highestSequence(in feed: FeedKey) -> UInt64? { highest[feed] }

    public func entry(named hash: EntryHash) -> Entry? {
        allEntries.first { $0.hash == hash }
    }

    public func entries(in feed: FeedKey, at seq: UInt64) -> [Entry] {
        feeds[feed]?[seq].map { Array($0.values) } ?? []
    }

    public func heads(of authors: Set<ParticipantID>) -> VectorClock {
        var clock = VectorClock()
        for (feed, top) in highest where authors.contains(feed.author) {
            clock.observe(feed, seq: top)
        }
        return clock
    }

    public func gaps(from authors: Set<ParticipantID>? = nil) -> [FeedGap] {
        let keys = Set(highest.keys).union(claimed.keys).filter { key in
            registries[key.author] != nil && (authors?.contains(key.author) ?? true)
        }
        var found: [FeedGap] = []
        for key in keys.sorted(by: { $0.canonicalBytes.lexicographicallyPrecedes($1.canonicalBytes) }) {
            let run = contiguous[key] ?? 0
            let top = Swift.max(highest[key] ?? 0, claimed[key])
            guard top > run else { continue }
            let held = scattered[key] ?? []
            let missing = ((run + 1)...top).filter { !held.contains($0) }
            if !missing.isEmpty {
                found.append(FeedGap(feed: key, spans: FeedGap.spans(of: missing)))
            }
        }
        return found
    }
}
