import Foundation

public struct PairHint: Hashable, Sendable, Codable {
    public let rawValue: Data

    public init(rawValue: Data) {
        self.rawValue = rawValue
    }
}

public struct PairLink: Hashable, Sendable, Codable {
    public let account: String
    public let url: URL

    public init(account: String, url: URL) {
        self.account = account
        self.url = url
    }
}

public enum JoinOutcome: Hashable, Sendable {
    case joined
    case notYetNamed
    case gone
}

public struct Pairs: Hashable, Sendable {
    public let me: ParticipantID
    public let hints: [ParticipantID: PairHint]
    public let accounts: [ParticipantID: Set<String>]

    public init(me: ParticipantID, hints: [ParticipantID: PairHint], accounts: [ParticipantID: Set<String>] = [:]) {
        self.me = me
        self.hints = hints
        self.accounts = accounts
    }

    public func peer(for hint: PairHint) -> ParticipantID? {
        hints.first { $0.value == hint }?.key
    }

    public func reads(_ peer: ParticipantID, from account: String) -> Bool {
        guard let owners = accounts[peer], !owners.isEmpty else { return true }
        return owners.contains(account)
    }

    public func hint(for peer: ParticipantID) throws -> PairHint {
        guard let hint = hints[peer] else { throw MailboxError.unknownPeer }
        return hint
    }
}

public enum PairWire {
    public static let infoRecord = "pair-info"
    public static let infoType = "PairInfo"
    public static let hint = "hint"

    public static let ringRecord = "ring"
    public static let ringType = "PairRing"
    public static let ring = "ring"

    public static func ringValue() -> String {
        Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }).lowercaseHex
    }

    public static let receiptType = "PairReceipt"
    public static let receiptTag = "tag"
    public static let receiptSealed = "sealed"

    public static func receiptName(for packet: PacketID) -> String {
        "receipt-" + packet.rawValue.uuidString
    }

    public static func receiptName(for attachment: AttachmentID) -> String {
        "photo-receipt-" + attachment.rawValue.uuidString
    }

    public static func packet(fromReceiptName name: String) -> PacketID? {
        guard name.hasPrefix("receipt-"), let uuid = UUID(uuidString: String(name.dropFirst("receipt-".count)))
        else { return nil }
        return PacketID(rawValue: uuid)
    }

    public static func attachment(fromReceiptName name: String) -> AttachmentID? {
        guard name.hasPrefix("photo-receipt-"),
            let uuid = UUID(uuidString: String(name.dropFirst("photo-receipt-".count)))
        else { return nil }
        return AttachmentID(rawValue: uuid)
    }
}
