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

    public let positions: [ConversationID: EntryLink]
    public let revocations: [DeviceRevocation]
    public let uploadsLeftForOthers: [AttachmentID]
    public let answeredDepartures: Set<EntryHash>
    public let greetedRooms: [ConversationID]
    public let readThrough: [ConversationID: EntryHash]
    public let organisation: RoomsListOrganisation?
    public let identities: [IdentityPublicKeys]

    private enum CodingKeys: String, CodingKey {
        case member, writtenAt, entries, certificates, epochs, preferences
        case positions, revocations, uploadsLeftForOthers, answeredDepartures, greetedRooms
        case readThrough, organisation, identities
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
        positions =
            try container.decodeIfPresent([ConversationID: EntryLink].self, forKey: .positions) ?? [:]
        revocations =
            try container.decodeIfPresent([DeviceRevocation].self, forKey: .revocations) ?? []
        uploadsLeftForOthers =
            try container.decodeIfPresent([AttachmentID].self, forKey: .uploadsLeftForOthers) ?? []
        answeredDepartures =
            try container.decodeIfPresent(Set<EntryHash>.self, forKey: .answeredDepartures) ?? []
        greetedRooms =
            try container.decodeIfPresent([ConversationID].self, forKey: .greetedRooms) ?? []
        readThrough =
            try container.decodeIfPresent([ConversationID: EntryHash].self, forKey: .readThrough) ?? [:]
        organisation =
            try container.decodeIfPresent(RoomsListOrganisation.self, forKey: .organisation)
        identities =
            try container.decodeIfPresent([IdentityPublicKeys].self, forKey: .identities) ?? []
    }

    public init(
        entries: [Entry],
        certificates: [DeviceCertificate],
        epochs: [HeldEpoch] = [],
        member: ParticipantID? = nil,
        writtenAt: Date? = nil,
        preferences: MemberPreferences = MemberPreferences(),
        positions: [ConversationID: EntryLink] = [:],
        revocations: [DeviceRevocation] = [],
        uploadsLeftForOthers: [AttachmentID] = [],
        answeredDepartures: Set<EntryHash> = [],
        greetedRooms: [ConversationID] = [],
        readThrough: [ConversationID: EntryHash] = [:],
        organisation: RoomsListOrganisation? = nil,
        identities: [IdentityPublicKeys] = []
    ) {
        self.member = member
        self.writtenAt = writtenAt
        self.entries = entries
        self.certificates = certificates
        self.epochs = epochs
        self.preferences = preferences
        self.positions = positions
        self.revocations = revocations
        self.uploadsLeftForOthers = uploadsLeftForOthers
        self.answeredDepartures = answeredDepartures
        self.greetedRooms = greetedRooms
        self.readThrough = readThrough
        self.organisation = organisation
        self.identities = identities
    }

    public func withoutEntries() -> SiblingFeed {
        SiblingFeed(
            entries: [], certificates: certificates, epochs: epochs, member: member,
            writtenAt: writtenAt, preferences: preferences, positions: positions,
            revocations: revocations, uploadsLeftForOthers: uploadsLeftForOthers,
            answeredDepartures: answeredDepartures, greetedRooms: greetedRooms,
            readThrough: readThrough, organisation: organisation, identities: identities)
    }
}

public struct DeviceRecords: Sendable, Hashable {
    public let summary: SealedSiblingFeed
    public let entries: SealedSiblingFeed?

    public init(summary: SealedSiblingFeed, entries: SealedSiblingFeed?) {
        self.summary = summary
        self.entries = entries
    }

    public static func seal(
        _ feed: SiblingFeed, for identity: Identity, on device: DeviceID, withEntries: Bool = true
    ) throws -> DeviceRecords {
        DeviceRecords(
            summary: try SealedSiblingFeed.seal(feed.withoutEntries(), for: identity, on: device),
            entries: withEntries ? try SealedSiblingFeed.seal(feed, for: identity, on: device) : nil)
    }
}

public struct DeviceRecordsSaved: Sendable, Hashable {
    public let summary: Bool
    public let entries: Bool

    public init(summary: Bool, entries: Bool) {
        self.summary = summary
        self.entries = entries
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
