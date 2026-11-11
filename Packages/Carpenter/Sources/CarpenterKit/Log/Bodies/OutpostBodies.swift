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

    public let chosenIn: RoomID?

    public init(
        person: ParticipantID, isAllowed: Bool, from: Date? = nil,
        origin: OutpostAccess.Origin = .chosen, sinceEpoch: UInt64? = nil,
        chosenIn: RoomID? = nil
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
        isAllowed = try container.decode(Bool.self, forKey: .isAllowed)
        from = try container.decodeIfPresent(Date.self, forKey: .from)
        origin = try container.decode(OutpostAccess.Origin.self, forKey: .origin)
        sinceEpoch = try container.decodeIfPresent(UInt64.self, forKey: .sinceEpoch)
        chosenIn = try container.decodeIfPresent(RoomID.self, forKey: .chosenIn)
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
        total = Swift.max(0, try container.decode(Int.self, forKey: .total))
    }
}
