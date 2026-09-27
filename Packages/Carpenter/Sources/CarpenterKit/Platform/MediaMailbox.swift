import Foundation

public struct OutgoingAttachment: Hashable, Sendable {
    public let id: AttachmentID
    public let ciphertext: Data
    public let recipients: Set<RecipientTag>

    public init(id: AttachmentID, ciphertext: Data, recipients: Set<RecipientTag>) {
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
    func upload(_ attachment: OutgoingAttachment) async throws

    func download(_ id: AttachmentID, hint tags: Set<RecipientTag>) async throws -> Data?

    func acknowledge(attachment id: AttachmentID, with receipt: SealedReceipt) async throws

    func pendingAttachments() async throws -> [AttachmentID: SentAttachment]

    func sweepableAttachments() async throws -> [AttachmentID: Date]

    func delete(attachment id: AttachmentID) async throws
}

public enum AttachmentWire {
    public static let attachmentID = "attachmentID"
    public static let outstanding = PacketWire.outstanding
    public static let blob = "blob"

    public static func fields(of attachment: OutgoingAttachment) -> [String: PacketField] {
        let recipients = attachment.recipients
            .map(\.rawValue)
            .sorted { $0.lexicographicallyPrecedes($1) }
        return [
            attachmentID: .string(attachment.id.rawValue.uuidString),
            outstanding: .dataList(recipients),
            blob: .data(attachment.ciphertext),
        ]
    }

    public static func sent(from fields: [String: PacketField]) -> SentAttachment {
        let recipients: Set<RecipientTag> =
            if case .dataList(let tags)? = fields[outstanding] { Set(tags.map(RecipientTag.init(rawValue:))) } else { [] }
        return SentAttachment(recipients: recipients, receipts: PacketWire.receipts(in: fields))
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
