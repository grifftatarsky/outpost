import Foundation

public enum PacketField: Hashable, Sendable {
    case string(String)
    case data(Data)
    case dataList([Data])
}

public enum PacketWire {
    public static let packetID = "packetID"
    public static let outstanding = "outstanding"
    public static let wrapTags = "wrapTags"
    public static let wrapValues = "wrapValues"
    public static let ciphertext = "ciphertext"
    public static let grantTags = "grantTags"
    public static let grantValues = "grantValues"

    public static func fields(of packet: SyncPacket) -> [String: PacketField] {
        let wraps = packet.wraps.sorted {
            $0.key.rawValue.lexicographicallyPrecedes($1.key.rawValue)
        }
        let grants =
            packet.grants
            .sorted { $0.key.rawValue.lexicographicallyPrecedes($1.key.rawValue) }
            .flatMap { tag, values in
                values.sorted { $0.lexicographicallyPrecedes($1) }.map { (key: tag, value: $0) }
            }

        return [
            packetID: .string(packet.id.rawValue.uuidString),
            outstanding: .dataList(wraps.map(\.key.rawValue)),
            wrapTags: .dataList(wraps.map(\.key.rawValue)),
            wrapValues: .dataList(wraps.map(\.value)),
            ciphertext: .data(packet.ciphertext),
            grantTags: .dataList(grants.map(\.key.rawValue)),
            grantValues: .dataList(grants.map(\.value)),
        ]
    }

    public static func packet(from fields: [String: PacketField]) -> SyncPacket? {
        guard case .string(let name)? = fields[packetID],
            let uuid = UUID(uuidString: name),
            case .dataList(let tags)? = fields[wrapTags],
            case .dataList(let values)? = fields[wrapValues],
            case .data(let payload)? = fields[ciphertext],
            tags.count == values.count
        else { return nil }

        let wraps = Dictionary(
            uniqueKeysWithValues: zip(tags.map(RecipientTag.init(rawValue:)), values))

        var grants: [RecipientTag: [Data]] = [:]
        if case .dataList(let grantKeys)? = fields[grantTags],
            case .dataList(let grantData)? = fields[grantValues],
            grantKeys.count == grantData.count
        {
            for (tag, value) in zip(grantKeys.map(RecipientTag.init(rawValue:)), grantData) {
                grants[tag, default: []].append(value)
            }
        }

        return SyncPacket(
            id: PacketID(rawValue: uuid), wraps: wraps, ciphertext: payload, grants: grants)
    }

    public static func outstanding(in fields: [String: PacketField]) -> [Data] {
        guard case .dataList(let tags)? = fields[outstanding] else { return [] }
        return tags
    }
}
