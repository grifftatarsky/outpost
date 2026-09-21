import Foundation

// MARK: The wall: who reads it, and what is said under a post

public struct CommentBody: Hashable, Sendable, Codable {
    public let target: EntryHash
    public let text: String

    public init(target: EntryHash, text: String) {
        self.target = target
        self.text = text
    }
}

public struct OutpostAccessBody: Hashable, Sendable, Codable {
    public let person: ParticipantID
    public let isAllowed: Bool
    public let from: Date?
    public let origin: OutpostAccess.Origin
    public let sinceEpoch: UInt64?

    public let chosenIn: ConversationID?

    public init(
        person: ParticipantID, isAllowed: Bool, from: Date? = nil,
        origin: OutpostAccess.Origin = .chosen, sinceEpoch: UInt64? = nil,
        chosenIn: ConversationID? = nil
    ) {
        self.person = person
        self.isAllowed = isAllowed
        self.from = from
        self.origin = origin
        self.sinceEpoch = sinceEpoch
        self.chosenIn = chosenIn
    }

    private enum CodingKeys: String, CodingKey {
        case person, isAllowed, from, origin, sinceEpoch, chosenIn
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        person = try container.decode(ParticipantID.self, forKey: .person)
        isAllowed = try container.decodeIfPresent(Bool.self, forKey: .isAllowed) ?? false
        from = try container.decodeIfPresent(Date.self, forKey: .from)
        origin = try container.decodeIfPresent(OutpostAccess.Origin.self, forKey: .origin) ?? .chosen
        sinceEpoch = try container.decodeIfPresent(UInt64.self, forKey: .sinceEpoch)
        chosenIn = try container.decodeIfPresent(ConversationID.self, forKey: .chosenIn)
    }
}

public struct CommentTallyBody: Hashable, Sendable, Codable {
    public let post: EntryHash
    public let total: Int

    public init(post: EntryHash, total: Int) {
        self.post = post
        self.total = Swift.max(0, total)
    }

    private enum CodingKeys: String, CodingKey { case post, total }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        post = try container.decode(EntryHash.self, forKey: .post)
        total = Swift.max(0, try container.decodeIfPresent(Int.self, forKey: .total) ?? 0)
    }
}
