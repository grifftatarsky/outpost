import Foundation

public struct RecipientTag: Hashable, Sendable, Codable {
    public let rawValue: Data

    public init(rawValue: Data) {
        self.rawValue = rawValue
    }
}

public struct PacketID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct SyncPacket: Hashable, Sendable, Codable {
    public let id: PacketID

    public let wraps: [RecipientTag: Data]

    public let ciphertext: Data

    public let grants: [RecipientTag: [Data]]

    public var recipients: Set<RecipientTag> { Set(wraps.keys) }

    public init(
        id: PacketID = PacketID(),
        wraps: [RecipientTag: Data],
        ciphertext: Data,
        grants: [RecipientTag: [Data]] = [:]
    ) {
        self.id = id
        self.wraps = wraps
        self.ciphertext = ciphertext
        self.grants = grants
    }
}

public enum MailboxError: Error, Hashable, Sendable {
    case unavailable
    case unknownPacket
    case budgetExhausted
    case recordTooLarge(bytes: Int, ceiling: Int)
}

public enum MailboxRules {
    public static let recordByteCeiling = 1_000_000

    public static let sweepAge: TimeInterval = 60 * 60

    public static func weigh(_ fields: [String: PacketField]) -> Int {
        fields.values.reduce(0) { total, field in
            switch field {
            case .string(let value): return total + value.utf8.count
            case .data(let value): return total + value.count
            case .dataList(let value): return total + value.reduce(0) { $0 + $1.count }
            }
        }
    }
}

public struct AcknowledgementFailure: Error, CustomStringConvertible, Sendable {
    public let failed: [PacketID: String]
    public let acknowledged: Int

    public init(failed: [PacketID: String], acknowledged: Int) {
        self.failed = failed
        self.acknowledged = acknowledged
    }

    public var description: String {
        let named = failed
            .sorted { $0.key.rawValue.uuidString < $1.key.rawValue.uuidString }
            .map { "\($0.key.rawValue.uuidString.prefix(8)): \($0.value)" }
            .joined(separator: "; ")
        return "\(failed.count) of \(failed.count + acknowledged) packet(s) not acknowledged — \(named)"
    }
}

public struct MessageBell: Hashable, Sendable {
    public let fetchTag: RecipientTag

    public let name: String

    public let ring: UInt64

    public init(fetchTag: RecipientTag, name: String, ring: UInt64) {
        self.fetchTag = fetchTag
        self.name = name
        self.ring = ring
    }
}

public protocol Mailbox: Sendable {
    func put(_ packet: SyncPacket) async throws

    func fetch(for tags: Set<RecipientTag>) async throws -> [SyncPacket]

    func acknowledge(_ id: PacketID, by tags: Set<RecipientTag>) async throws

    func pendingDeliveries() async throws -> [PacketID: Set<RecipientTag>]

    func ring(_ bell: MessageBell) async throws
}

extension Mailbox {
    public func pendingRecipients() async throws -> Set<RecipientTag> {
        try await pendingDeliveries().values.reduce(into: Set<RecipientTag>()) { $0.formUnion($1) }
    }

    public func fetch(for tag: RecipientTag) async throws -> [SyncPacket] {
        try await fetch(for: [tag])
    }

    public func acknowledge(_ id: PacketID, by tag: RecipientTag) async throws {
        try await acknowledge(id, by: [tag])
    }
}
