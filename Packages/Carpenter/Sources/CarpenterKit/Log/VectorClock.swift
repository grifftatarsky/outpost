import Foundation

public struct FeedKey: Hashable, Sendable, Codable {
    public let author: ParticipantID
    public let device: DeviceID

    public init(author: ParticipantID, device: DeviceID) {
        self.author = author
        self.device = device
    }

    var canonicalBytes: Data { author.rawValue + device.rawValue }
}

public struct VectorClock: Hashable, Sendable, Codable {
    private var frontier: [FeedKey: UInt64]

    public init() {
        frontier = [:]
    }

    public subscript(key: FeedKey) -> UInt64 {
        get { frontier[key] ?? 0 }
        set { frontier[key] = newValue == 0 ? nil : newValue }
    }

    public var keys: Set<FeedKey> { Set(frontier.keys) }

    public var isEmpty: Bool { frontier.isEmpty }

    public mutating func observe(_ key: FeedKey, seq: UInt64) {
        guard seq > self[key] else { return }
        self[key] = seq
    }

    public func merging(_ other: VectorClock) -> VectorClock {
        var merged = self
        for (key, seq) in other.frontier {
            merged.observe(key, seq: seq)
        }
        return merged
    }

    public func happensBefore(_ other: VectorClock) -> Bool {
        guard self != other else { return false }
        return frontier.allSatisfy { key, seq in seq <= other[key] }
    }

    public func isConcurrent(with other: VectorClock) -> Bool {
        self != other && !happensBefore(other) && !other.happensBefore(self)
    }

    var canonicalBytes: Data {
        let sorted = frontier
            .sorted { $0.key.canonicalBytes.lexicographicallyPrecedes($1.key.canonicalBytes) }

        return CanonicalBytes.payload(
            domain: Domain.vectorClock,
            fields: sorted.flatMap { [$0.key.canonicalBytes, CanonicalBytes.sequence($0.value)] }
        )
    }
}
