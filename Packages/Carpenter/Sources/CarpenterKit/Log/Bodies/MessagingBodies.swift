import Foundation

// MARK: What is said in a room, and what happens to it

public struct PostBody: Hashable, Sendable, Codable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct EditBody: Hashable, Sendable, Codable {
    public let target: EntryHash
    public let text: String

    public init(target: EntryHash, text: String) {
        self.target = target
        self.text = text
    }
}

public struct TombstoneBody: Hashable, Sendable, Codable {
    public let target: EntryHash

    public init(target: EntryHash) {
        self.target = target
    }
}

public struct ReadPolicyBody: Hashable, Sendable, Codable {
    public let reports: Bool

    public init(reports: Bool) {
        self.reports = reports
    }
}

public struct ReadReceiptBody: Hashable, Sendable, Codable {
    public let target: EntryHash

    public init(target: EntryHash) {
        self.target = target
    }
}

public struct ReactionBody: Hashable, Sendable, Codable {
    public let target: EntryHash
    public let emoji: String?

    public init(target: EntryHash, emoji: String?) {
        self.target = target
        self.emoji = emoji
    }
}
