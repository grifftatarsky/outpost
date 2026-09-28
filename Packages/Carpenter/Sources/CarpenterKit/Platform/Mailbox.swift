import CryptoKit
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

    public var storedAt: Date?

    public var from: ParticipantID?

    public var receipts: [SealedReceipt] = []

    public var recipients: Set<RecipientTag> { Set(wraps.keys) }

    private enum CodingKeys: String, CodingKey {
        case id, wraps, ciphertext, grants
    }

    public init(
        id: PacketID = PacketID(),
        wraps: [RecipientTag: Data],
        ciphertext: Data,
        grants: [RecipientTag: [Data]] = [:],
        storedAt: Date? = nil
    ) {
        self.id = id
        self.wraps = wraps
        self.ciphertext = ciphertext
        self.grants = grants
        self.storedAt = storedAt
    }
}

public enum MailboxError: Error, Hashable, Sendable {
    case unavailable
    case unknownPacket
    case unknownPeer
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

public struct SealedReceipt: Hashable, Sendable, Codable {
    public let tag: RecipientTag
    public let sealed: Data

    public init(tag: RecipientTag, sealed: Data) {
        self.tag = tag
        self.sealed = sealed
    }
}

public struct PacketReceipt: Hashable, Sendable, Codable {
    public let participant: ParticipantID
    public let device: DeviceID
    public let signature: Data

    static func signed(
        _ packet: PacketID, participant: ParticipantID, device: DeviceID, domain: String = Domain.packetReceipt
    ) -> Data {
        CanonicalBytes.payload(
            domain: domain,
            fields: [CanonicalBytes.uuid(packet.rawValue), participant.rawValue, device.rawValue])
    }

    static func context(_ packet: PacketID, tag: RecipientTag, domain: String = Domain.packetReceipt) -> Data {
        CanonicalBytes.payload(
            domain: domain,
            fields: [CanonicalBytes.uuid(packet.rawValue), tag.rawValue])
    }

    public static func seal(
        _ packet: PacketID, under tag: RecipientTag, as participant: ParticipantID, by device: DeviceKeys,
        to peer: PairwiseSecret
    ) throws -> SealedReceipt {
        try seal(packet, under: tag, as: participant, by: device, to: peer, domain: Domain.packetReceipt)
    }

    static func seal(
        _ packet: PacketID, under tag: RecipientTag, as participant: ParticipantID, by device: DeviceKeys,
        to peer: PairwiseSecret, domain: String
    ) throws -> SealedReceipt {
        let receipt = PacketReceipt(
            participant: participant, device: device.id,
            signature: try device.sign(signed(packet, participant: participant, device: device.id, domain: domain)))
        return SealedReceipt(
            tag: tag,
            sealed: try peer.wrap(
                try JSONEncoder().encode(receipt), context: context(packet, tag: tag, domain: domain)))
    }

    public static func open(
        _ sealed: SealedReceipt, for packet: PacketID, from participant: ParticipantID, with peer: PairwiseSecret,
        by registry: DeviceRegistry
    ) -> PacketReceipt? {
        open(sealed, for: packet, from: participant, with: peer, by: registry, domain: Domain.packetReceipt)
    }

    static func open(
        _ sealed: SealedReceipt, for packet: PacketID, from participant: ParticipantID, with peer: PairwiseSecret,
        by registry: DeviceRegistry, domain: String
    ) -> PacketReceipt? {
        guard
            let plaintext = try? peer.unwrap(
                sealed.sealed, context: context(packet, tag: sealed.tag, domain: domain)),
            let receipt = try? JSONDecoder().decode(PacketReceipt.self, from: plaintext),
            receipt.participant == participant,
            registry.activeDevices.contains(receipt.device),
            let key = registry.signingKey(for: receipt.device),
            (try? DeviceKeys.isValidSignature(
                receipt.signature,
                for: signed(packet, participant: participant, device: receipt.device, domain: domain),
                publicKey: key)) == true
        else { return nil }
        return receipt
    }
}

public enum AttachmentReceipt {
    public static func seal(
        _ attachment: AttachmentID, under tag: RecipientTag, as participant: ParticipantID, by device: DeviceKeys,
        to peer: PairwiseSecret
    ) throws -> SealedReceipt {
        try PacketReceipt.seal(
            PacketID(rawValue: attachment.rawValue), under: tag, as: participant, by: device, to: peer,
            domain: Domain.attachmentReceipt)
    }

    public static func open(
        _ sealed: SealedReceipt, for attachment: AttachmentID, from participant: ParticipantID,
        with peer: PairwiseSecret, by registry: DeviceRegistry
    ) -> PacketReceipt? {
        PacketReceipt.open(
            sealed, for: PacketID(rawValue: attachment.rawValue), from: participant, with: peer, by: registry,
            domain: Domain.attachmentReceipt)
    }
}

public struct SentPacket: Hashable, Sendable {
    public let to: ParticipantID
    public let recipients: Set<RecipientTag>
    public let receipts: [SealedReceipt]
    public let createdAt: Date?
    public let contentDigest: Data?

    public init(
        to: ParticipantID, recipients: Set<RecipientTag>, receipts: [SealedReceipt], createdAt: Date?,
        contentDigest: Data? = nil
    ) {
        self.to = to
        self.recipients = recipients
        self.receipts = receipts
        self.createdAt = createdAt
        self.contentDigest = contentDigest
    }
}

extension SyncPacket {
    public var contentDigest: Data {
        let byTag: (RecipientTag, RecipientTag) -> Bool = { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
        var fields = [Data(id.rawValue.uuidString.utf8), count(wraps.count)]
        for tag in wraps.keys.sorted(by: byTag) {
            fields.append(tag.rawValue)
            fields.append(wraps[tag] ?? Data())
        }
        fields.append(ciphertext)
        let granted = grants.filter { !$0.value.isEmpty }
        fields.append(count(granted.count))
        for tag in granted.keys.sorted(by: byTag) {
            let values = (grants[tag] ?? []).sorted { $0.lexicographicallyPrecedes($1) }
            fields.append(tag.rawValue)
            fields.append(count(values.count))
            fields.append(contentsOf: values)
        }
        return Data(SHA256.hash(data: CanonicalBytes.payload(domain: Domain.packetContent, fields: fields)))
    }

    private func count(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(clamping: value).bigEndian) { Data($0) }
    }
}

public protocol Mailbox: Sendable {
    func account(in pairs: Pairs) async throws -> String

    func space(for peer: ParticipantID, naming account: String?, in pairs: Pairs) async throws -> URL

    func spaceForACode(in pairs: Pairs) async throws -> URL

    func claim(_ url: URL, for peer: ParticipantID, naming account: String?, in pairs: Pairs) async throws -> URL

    func join(_ link: PairLink, of peer: ParticipantID, in pairs: Pairs) async throws -> JoinOutcome

    func reads(_ peer: ParticipantID, in pairs: Pairs) async throws -> Bool

    func close(_ peer: ParticipantID, in pairs: Pairs) async throws

    func put(_ packet: SyncPacket, to peer: ParticipantID, in pairs: Pairs) async throws

    func ring(_ peer: ParticipantID, in pairs: Pairs) async throws

    func fetch(from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs) async throws -> [SyncPacket]

    func acknowledge(
        _ id: PacketID, from peer: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs) async throws

    func sentPackets(in pairs: Pairs) async throws -> [PacketID: SentPacket]

    func withdraw(_ id: PacketID, in pairs: Pairs) async throws
}
