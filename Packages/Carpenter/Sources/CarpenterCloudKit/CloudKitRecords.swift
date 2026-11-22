import CloudKit
import CarpenterKit
import Foundation

enum PacketRecord {
    static let type = PushChannel.inbox.recordType

    static func write(_ fields: [String: PacketField], into record: CKRecord) {
        for (key, field) in fields {
            switch field {
            case .string(let value): record[key] = value
            case .data(let value): record[key] = value
            case .dataList(let value): record[key] = value
            }
        }
    }

    static func read(_ record: CKRecord) -> SyncPacket? {
        PacketWire.packet(from: PairIndex.Cached(record).fields)
    }
}

enum AttachmentRecord {
    static let type = "Attachment"
}

extension AttachmentID {
    var recordName: String { rawValue.uuidString }
}

extension PacketID {
    var recordName: String { rawValue.uuidString }

    init?(recordName: String) {
        guard let uuid = UUID(uuidString: recordName) else { return nil }
        self.init(rawValue: uuid)
    }
}
