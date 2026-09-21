import CryptoKit
import Foundation

public struct HeldEpoch: Hashable, Sendable, Codable {
    public let room: ConversationID
    public let epoch: EpochNumber
    public let material: Data

    public init(room: ConversationID, epoch: EpochNumber, material: Data) {
        self.room = room
        self.epoch = epoch
        self.material = material
    }
}

public struct SiblingFeed: Hashable, Sendable, Codable {
    public let member: ParticipantID?

    public let writtenAt: Date?

    public let entries: [Entry]
    public let certificates: [DeviceCertificate]

    public let epochs: [HeldEpoch]

    public let preferences: MemberPreferences

    private enum CodingKeys: String, CodingKey {
        case member, writtenAt, entries, certificates, epochs, preferences
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        member = try container.decodeIfPresent(ParticipantID.self, forKey: .member)
        writtenAt = try container.decodeIfPresent(Date.self, forKey: .writtenAt)
        entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        certificates =
            try container.decodeIfPresent([DeviceCertificate].self, forKey: .certificates) ?? []
        epochs = try container.decodeIfPresent([HeldEpoch].self, forKey: .epochs) ?? []
        preferences =
            try container.decodeIfPresent(MemberPreferences.self, forKey: .preferences)
            ?? MemberPreferences()
    }

    public init(
        entries: [Entry],
        certificates: [DeviceCertificate],
        epochs: [HeldEpoch] = [],
        member: ParticipantID? = nil,
        writtenAt: Date? = nil,
        preferences: MemberPreferences = MemberPreferences()
    ) {
        self.member = member
        self.writtenAt = writtenAt
        self.entries = entries
        self.certificates = certificates
        self.epochs = epochs
        self.preferences = preferences
    }
}

public struct SealedSiblingFeed: Hashable, Sendable, Codable {
    public let ciphertext: Data

    public init(ciphertext: Data) {
        self.ciphertext = ciphertext
    }

    private static func key(for identity: Identity) -> SymmetricKey {
        SymmetricKey(
            data: HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: identity.signingSeed + identity.agreementSeed),
                salt: Data(Domain.siblingFeed.utf8),
                info: CanonicalBytes.payload(
                    domain: Domain.siblingFeed, fields: [identity.id.rawValue]),
                outputByteCount: 32))
    }

    private static func context(member: ParticipantID, device: DeviceID) -> Data {
        CanonicalBytes.payload(
            domain: Domain.siblingFeed, fields: [member.rawValue, device.rawValue])
    }

    public static func seal(_ feed: SiblingFeed, for identity: Identity, on device: DeviceID) throws
        -> SealedSiblingFeed
    {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let box = try ChaChaPoly.seal(
            try encoder.encode(feed),
            using: key(for: identity),
            authenticating: context(member: identity.id, device: device))
        return SealedSiblingFeed(ciphertext: box.combined)
    }

    public func open(with identity: Identity, from device: DeviceID) throws -> SiblingFeed {
        guard let box = try? ChaChaPoly.SealedBox(combined: ciphertext) else {
            throw CryptoError.openFailed
        }
        guard let plaintext = try? ChaChaPoly.open(
            box, using: Self.key(for: identity),
            authenticating: Self.context(member: identity.id, device: device))
        else {
            throw CryptoError.openFailed
        }
        return try JSONDecoder().decode(SiblingFeed.self, from: plaintext)
    }
}
