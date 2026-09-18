import CloudKit
import CarpenterKit
import Foundation

enum PacketRecord {
    static let type = PushChannel.inbox.recordType

    static func write(_ packet: SyncPacket, into record: CKRecord) throws {
        for (key, field) in PacketWire.fields(of: packet) {
            switch field {
            case .string(let value): record[key] = value
            case .data(let value): record[key] = value
            case .dataList(let value): record[key] = value
            }
        }
    }

    static func read(_ record: CKRecord) -> SyncPacket? {
        var fields: [String: PacketField] = [:]
        for key in record.allKeys() {
            switch record[key] {
            case let value as String: fields[key] = .string(value)
            case let value as [Data]: fields[key] = .dataList(value)
            case let value as Data: fields[key] = .data(value)
            default: continue
            }
        }
        return PacketWire.packet(from: fields)
    }
}

enum AttachmentRecord {
    static let type = "Attachment"

    static func write(_ attachment: OutgoingAttachment, into record: CKRecord) throws -> URL {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "\(attachment.id.rawValue.uuidString).sealed")
        for (key, field) in AttachmentWire.fields(of: attachment) {
            switch (key, field) {
            case (AttachmentWire.blob, .data(let bytes)):
                try bytes.write(to: scratch, options: .atomic)
                record[key] = CKAsset(fileURL: scratch)
            case (_, .string(let value)): record[key] = value
            case (_, .data(let value)): record[key] = value
            case (_, .dataList(let value)): record[key] = value
            }
        }
        return scratch
    }
}

extension AttachmentID {
    var recordName: String { rawValue.uuidString }

    init?(recordName: String) {
        guard let uuid = UUID(uuidString: recordName) else { return nil }
        self.init(rawValue: uuid)
    }
}

extension PacketID {
    var recordName: String { rawValue.uuidString }

    init?(recordName: String) {
        guard let uuid = UUID(uuidString: recordName) else { return nil }
        self.init(rawValue: uuid)
    }
}
