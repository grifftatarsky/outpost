import CryptoKit
import Foundation

public struct HeldEpoch: Hashable, Sendable, Codable {
    public let room: RoomID
    public let epoch: EpochNumber
    public let material: Data

    public init(room: RoomID, epoch: EpochNumber, material: Data) {
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

    public let collected: [SiblingCursor]

    public let through: Int?

    public let revocations: [DeviceRevocation]

    public let forwarded: [ForwardedGrant]

    public let people: [IdentityPublicKeys]

    private enum CodingKeys: String, CodingKey {
        case member, writtenAt, entries, certificates, epochs, preferences, collected, through
        case revocations, forwarded, people
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
        collected = try container.decodeIfPresent([SiblingCursor].self, forKey: .collected) ?? []
        through = try container.decodeIfPresent(Int.self, forKey: .through)
        revocations = try container.decodeIfPresent([DeviceRevocation].self, forKey: .revocations) ?? []
        forwarded = try container.decodeIfPresent([ForwardedGrant].self, forKey: .forwarded) ?? []
        people = try container.decodeIfPresent([IdentityPublicKeys].self, forKey: .people) ?? []
    }

    public init(
        entries: [Entry],
        certificates: [DeviceCertificate],
        epochs: [HeldEpoch] = [],
        member: ParticipantID? = nil,
        writtenAt: Date? = nil,
        preferences: MemberPreferences = MemberPreferences(),
        collected: [SiblingCursor] = [],
        through: Int? = nil,
        revocations: [DeviceRevocation] = [],
        forwarded: [ForwardedGrant] = [],
        people: [IdentityPublicKeys] = []
    ) {
        self.member = member
        self.writtenAt = writtenAt
        self.entries = entries
        self.certificates = certificates
        self.epochs = epochs
        self.preferences = preferences
        self.collected = collected
        self.through = through
        self.revocations = revocations
        self.forwarded = forwarded
        self.people = people
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

    private static func context(
        member: ParticipantID, device: DeviceID, kind: SiblingRecord.Kind
    ) -> Data {
        switch kind {
        case .state:
            CanonicalBytes.payload(
                domain: Domain.siblingFeed, fields: [member.rawValue, device.rawValue])
        case .mail(let number):
            CanonicalBytes.payload(
                domain: Domain.siblingFeed,
                fields: [member.rawValue, device.rawValue, Data("mail \(number)".utf8)])
        case .catchUp(let target):
            CanonicalBytes.payload(
                domain: Domain.siblingFeed,
                fields: [member.rawValue, device.rawValue, Data("catch-up".utf8), target.rawValue])
        case .request:
            CanonicalBytes.payload(
                domain: Domain.siblingFeed, fields: [member.rawValue, device.rawValue, Data("request".utf8)])
        case .approval(let target):
            CanonicalBytes.payload(
                domain: Domain.siblingFeed,
                fields: [member.rawValue, device.rawValue, Data("approval".utf8), target.rawValue])
        case .authority(let digest):
            CanonicalBytes.payload(
                domain: Domain.siblingFeed,
                fields: [member.rawValue, device.rawValue, Data("authority".utf8), digest])
        }
    }

    public static func seal(
        _ feed: SiblingFeed, for identity: Identity, on device: DeviceID,
        as kind: SiblingRecord.Kind = .state, to recipients: [DeviceRecipient] = []
    ) throws -> SealedSiblingFeed {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let context = context(member: identity.id, device: device, kind: kind)
        let inner = try ChaChaPoly.seal(
            try encoder.encode(feed), using: key(for: identity), authenticating: context
        ).combined
        guard !recipients.isEmpty else { return SealedSiblingFeed(ciphertext: inner) }

        let content = SymmetricKey(size: .bits256)
        let envelope = Envelope(
            seals: try recipients.map {
                try DeviceSeal.seal(content.withUnsafeBytes { Data($0) }, to: $0, context: context)
            },
            box: try ChaChaPoly.seal(inner, using: content, authenticating: context).combined)
        return SealedSiblingFeed(ciphertext: Self.envelopeMark + (try encoder.encode(envelope)))
    }

    @concurrent
    public static func sealInBackground(
        _ feed: SiblingFeed, for identity: Identity, on device: DeviceID,
        as kind: SiblingRecord.Kind = .state, to recipients: [DeviceRecipient] = []
    ) async throws -> SealedSiblingFeed {
        try seal(feed, for: identity, on: device, as: kind, to: recipients)
    }

    @concurrent
    public func openInBackground(
        with identity: Identity, from device: DeviceID, as kind: SiblingRecord.Kind = .state,
        reading reader: DeviceKeys? = nil
    ) async throws -> SiblingFeed {
        try open(with: identity, from: device, as: kind, reading: reader)
    }

    public func open(
        with identity: Identity, from device: DeviceID, as kind: SiblingRecord.Kind = .state,
        reading reader: DeviceKeys? = nil
    ) throws -> SiblingFeed {
        let context = Self.context(member: identity.id, device: device, kind: kind)
        var inner = ciphertext
        if ciphertext.starts(with: Self.envelopeMark) {
            guard
                let envelope = try? JSONDecoder().decode(
                    Envelope.self, from: ciphertext.dropFirst(Self.envelopeMark.count))
            else { throw CryptoError.openFailed }
            guard let reader, let seal = envelope.seals.first(where: { $0.device == reader.id }) else {
                throw CryptoError.notSealedForThisDevice
            }
            let content = SymmetricKey(data: try seal.open(with: reader, context: context))
            guard let box = try? ChaChaPoly.SealedBox(combined: envelope.box),
                let opened = try? ChaChaPoly.open(box, using: content, authenticating: context)
            else { throw CryptoError.openFailed }
            inner = opened
        }
        guard let box = try? ChaChaPoly.SealedBox(combined: inner),
            let plaintext = try? ChaChaPoly.open(
                box, using: Self.key(for: identity), authenticating: context)
        else {
            throw CryptoError.openFailed
        }
        return try JSONDecoder().decode(SiblingFeed.self, from: plaintext)
    }

    private struct Envelope: Codable {
        let seals: [DeviceSeal]
        let box: Data
    }

    private static let envelopeMark = Data("carpenter.devices.v1\n".utf8)
}
