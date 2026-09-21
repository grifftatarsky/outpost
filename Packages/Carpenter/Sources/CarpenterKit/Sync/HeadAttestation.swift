import Foundation

public struct HeadAttestation: Hashable, Sendable, Codable {
    public let feed: FeedKey
    public let head: EntryLink

    public init(feed: FeedKey, head: EntryLink) {
        self.feed = feed
        self.head = head
    }
}

public struct Contradiction: Hashable, Sendable, Codable {
    public let feed: FeedKey
    public let seq: UInt64
    public let held: EntryHash
    public let attested: EntryHash
    public let by: ParticipantID

    public init(feed: FeedKey, seq: UInt64, held: EntryHash, attested: EntryHash, by: ParticipantID) {
        self.feed = feed
        self.seq = seq
        self.held = held
        self.attested = attested
        self.by = by
    }
}

extension Replica {
    public func contradictions(
        in attestations: [HeadAttestation], from observer: ParticipantID
    ) -> [Contradiction] {
        attestations.compactMap { attestation in
            let held = entries(in: attestation.feed, at: attestation.head.seq)
            guard !held.isEmpty, !held.contains(where: { $0.hash == attestation.head.hash }),
                let first = held.map(\.hash).min(by: { $0.rawValue.lexicographicallyPrecedes($1.rawValue) })
            else { return nil }
            return Contradiction(
                feed: attestation.feed, seq: attestation.head.seq, held: first,
                attested: attestation.head.hash, by: observer)
        }
    }

    public func tops(in conversation: ConversationID) -> [FeedKey: [Entry]] {
        var tops: [FeedKey: [Entry]] = [:]
        for entry in allEntries where entry.conversation == conversation {
            let current = tops[entry.feedKey]?.first?.seq ?? 0
            if entry.seq > current {
                tops[entry.feedKey] = [entry]
            } else if entry.seq == current {
                tops[entry.feedKey, default: []].append(entry)
            }
        }
        return tops
    }
}
