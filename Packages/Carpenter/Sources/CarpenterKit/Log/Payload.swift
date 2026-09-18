import Foundation

// MARK: The envelope every entry carries

public struct PayloadType: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let post = PayloadType(rawValue: 1)
    public static let edit = PayloadType(rawValue: 2)
    public static let tombstone = PayloadType(rawValue: 3)
    public static let reaction = PayloadType(rawValue: 4)

    public static let roomProfile = PayloadType(rawValue: 5)

    public static let comment = PayloadType(rawValue: 7)

    public static let joinRequest = PayloadType(rawValue: 8)

    public static let admission = PayloadType(rawValue: 9)

    public static let epochChange = PayloadType(rawValue: 10)

    public static let memberProfile = PayloadType(rawValue: 6)

    public static let roomAccess = PayloadType(rawValue: 11)

    public static let readReceipt = PayloadType(rawValue: 12)

    public static let readPolicy = PayloadType(rawValue: 13)

    public static let removal = PayloadType(rawValue: 14)

    public static let departure = PayloadType(rawValue: 15)

    public static let media = PayloadType(rawValue: 16)

    public static let memberPhoto = PayloadType(rawValue: 17)

    public static let focusStatus = PayloadType(rawValue: 18)
    public static let outpostAccess = PayloadType(rawValue: 19)

    public static let commentTally = PayloadType(rawValue: 20)

    public static let joinConfirmed = PayloadType(rawValue: 21)
    public static let invitationRescinded = PayloadType(rawValue: 22)
    public static let soloCheck = PayloadType(rawValue: 23)
    public static let supporterBadge = PayloadType(rawValue: 24)

    public static let allKnown: [PayloadType] = [
        .post, .edit, .tombstone, .reaction, .roomProfile, .memberProfile, .comment,
        .joinRequest, .admission, .epochChange, .roomAccess, .readReceipt, .readPolicy, .removal,
        .departure, .media, .memberPhoto, .focusStatus, .outpostAccess, .commentTally,
        .joinConfirmed, .invitationRescinded, .soloCheck, .supporterBadge,
    ]

    public static let plumbing: Set<PayloadType> = [
        .memberProfile, .roomProfile, .comment, .joinRequest, .admission, .epochChange,
        .roomAccess, .readReceipt, .readPolicy, .removal, .departure, .memberPhoto, .focusStatus,
        .outpostAccess, .commentTally, .joinConfirmed, .invitationRescinded, .soloCheck,
        .supporterBadge,
    ]

    var canonicalBytes: Data {
        withUnsafeBytes(of: rawValue.bigEndian) { Data($0) }
    }
}

public struct Payload: Hashable, Sendable, Codable {
    public let type: PayloadType
    public let version: Int

    public let body: Data

    public let fallbackText: String?

    public init(type: PayloadType, version: Int = 1, body: Data, fallbackText: String? = nil) {
        self.type = type
        self.version = version
        self.body = body
        self.fallbackText = fallbackText
    }

    var canonicalBytes: Data {
        CanonicalBytes.payload(
            domain: Domain.payload,
            fields: [
                type.canonicalBytes,
                CanonicalBytes.sequence(UInt64(bitPattern: Int64(version))),
                body,
            ] + CanonicalBytes.optional(fallbackText.map { Data($0.utf8) })
        )
    }
}
