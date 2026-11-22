import Foundation

public struct OutgoingAttachment: Hashable, Sendable {
    public let id: AttachmentID
    public let ciphertext: Data
    public let recipients: [ParticipantID: RecipientTag]

    public init(id: AttachmentID, ciphertext: Data, recipients: [ParticipantID: RecipientTag]) {
        self.id = id
        self.ciphertext = ciphertext
        self.recipients = recipients
    }

    public func copies(between secret: (ParticipantID) -> PairwiseSecret?) throws -> PhotoCopies {
        var copies: [ParticipantID: PhotoCopy] = [:]
        for (person, tag) in recipients {
            guard let pair = secret(person) else { continue }
            copies[person] = try PhotoCopy.seal(ciphertext, of: id, for: tag, between: pair)
        }
        return PhotoCopies(photo: id, copies: copies)
    }
}

public struct PhotoCopies: Hashable, Sendable {
    public let photo: AttachmentID
    public let copies: [ParticipantID: PhotoCopy]

    public init(photo: AttachmentID, copies: [ParticipantID: PhotoCopy]) {
        self.photo = photo
        self.copies = copies
    }
}

public struct StoredPhotoCopy: Hashable, Sendable {
    public let name: PhotoCopyName
    public let to: ParticipantID
    public let label: Data?
    public let recipients: Set<RecipientTag>
    public let receipts: [SealedReceipt]
    public let storedAt: Date
    public let modifiedAt: Date

    public init(
        name: PhotoCopyName, to: ParticipantID, label: Data?, recipients: Set<RecipientTag>, receipts: [SealedReceipt],
        storedAt: Date, modifiedAt: Date
    ) {
        self.name = name
        self.to = to
        self.label = label
        self.recipients = recipients
        self.receipts = receipts
        self.storedAt = storedAt
        self.modifiedAt = modifiedAt
    }
}

public struct SentAttachment: Hashable, Sendable {
    public let recipients: Set<RecipientTag>
    public let receipts: [SealedReceipt]

    public init(recipients: Set<RecipientTag>, receipts: [SealedReceipt]) {
        self.recipients = recipients
        self.receipts = receipts
    }
}

public protocol MediaMailbox: Sendable {
    func upload(_ copies: PhotoCopies, in pairs: Pairs) async throws

    func download(_ copy: PhotoCopyName, of photo: AttachmentID, from sender: ParticipantID, in pairs: Pairs)
        async throws -> Data?

    func acknowledge(
        copy: PhotoCopyName, from sender: ParticipantID, with receipt: SealedReceipt, by device: DeviceID,
        in pairs: Pairs
    ) async throws

    func ownCopy(_ copy: PhotoCopyName, in pairs: Pairs) async throws -> Data?

    func storedCopies(in pairs: Pairs) async throws -> [StoredPhotoCopy]

    func delete(copies: Set<PhotoCopyName>, in pairs: Pairs) async throws
}

public enum AttachmentWire {
    public static let label = "label"
    public static let outstanding = PacketWire.outstanding
    public static let blob = "blob"

    public static func fields(of copy: PhotoCopy) -> [String: PacketField] {
        [
            label: .data(copy.label),
            outstanding: .dataList([copy.tag.rawValue]),
            blob: .data(copy.sealed),
        ]
    }

    public static func recipients(in fields: [String: PacketField]) -> Set<RecipientTag> {
        if case .dataList(let tags)? = fields[outstanding] { Set(tags.map(RecipientTag.init(rawValue:))) } else { [] }
    }

    public static func sealedLabel(from fields: [String: PacketField]) -> Data? {
        if case .data(let bytes)? = fields[label] { bytes } else { nil }
    }

    public static func sealedCopy(from fields: [String: PacketField]) -> Data? {
        if case .data(let bytes)? = fields[blob] { bytes } else { nil }
    }

    public static func stored(
        _ name: PhotoCopyName, fields: [String: PacketField], to peer: ParticipantID, storedAt: Date, modifiedAt: Date,
        answeredBy answers: [(fields: [String: PacketField], modifiedAt: Date)]
    ) -> StoredPhotoCopy {
        StoredPhotoCopy(
            name: name, to: peer, label: sealedLabel(from: fields), recipients: recipients(in: fields),
            receipts: answers.filter { $0.modifiedAt >= modifiedAt }.compactMap { PacketWire.receipt(from: $0.fields) },
            storedAt: storedAt, modifiedAt: modifiedAt)
    }
}
