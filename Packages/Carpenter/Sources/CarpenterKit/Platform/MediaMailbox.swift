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
    func upload(_ attachment: OutgoingAttachment, in pairs: Pairs) async throws

    func download(_ id: AttachmentID, from sender: ParticipantID, in pairs: Pairs) async throws -> Data?

    func acknowledge(
        attachment id: AttachmentID, from sender: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs
    ) async throws

    func pendingAttachments(in pairs: Pairs) async throws -> [AttachmentID: SentAttachment]

    func sweepableAttachments(in pairs: Pairs) async throws -> [AttachmentID: Date]

    func delete(attachment id: AttachmentID, in pairs: Pairs) async throws
}

public enum AttachmentWire {
    public static let attachmentID = "attachmentID"
    public static let outstanding = PacketWire.outstanding
    public static let blob = "blob"

    public static func fields(of attachment: OutgoingAttachment, for tag: RecipientTag) -> [String: PacketField] {
        [
            attachmentID: .string(attachment.id.rawValue.uuidString),
            outstanding: .dataList([tag.rawValue]),
            blob: .data(attachment.ciphertext),
        ]
    }

    public static func recipients(in fields: [String: PacketField]) -> Set<RecipientTag> {
        if case .dataList(let tags)? = fields[outstanding] { Set(tags.map(RecipientTag.init(rawValue:))) } else { [] }
    }

    public static func attachment(from fields: [String: PacketField]) -> (
        id: AttachmentID, ciphertext: Data
    )? {
        guard case .string(let name)? = fields[attachmentID],
            let uuid = UUID(uuidString: name),
            case .data(let bytes)? = fields[blob]
        else { return nil }
        return (AttachmentID(rawValue: uuid), bytes)
    }
}
