import CryptoKit
import Foundation

public struct Peer: Sendable {
    public let secret: PairwiseSecret
    public let them: ParticipantID
    public let me: ParticipantID

    public init(secret: PairwiseSecret, them: ParticipantID, me: ParticipantID) {
        self.secret = secret
        self.them = them
        self.me = me
    }

    public func outgoingTag(window: UInt64) -> RecipientTag {
        secret.recipientTag(window: window, for: them)
    }

    public func incomingTag(window: UInt64) -> RecipientTag {
        secret.recipientTag(window: window, for: me)
    }
}

public enum SyncError: Error, Hashable, Sendable {
    case notAddressedToUs
    case packetUnreadable
}

public enum SyncEngine {
    public struct Delivery: Sendable {
        public let entries: [Entry]
        public let identities: [IdentityPublicKeys]
        public let certificates: [DeviceCertificate]
        public let revocations: [DeviceRevocation]
        public let grants: [EpochGrant]
        public let requests: [RepairRequest]
        public let answers: [RepairAnswer]
        public let notifyWalls: [ParticipantID]?
        public let confirmations: [JoinConfirmedBody]

        public init(
            entries: [Entry], certificates: [DeviceCertificate], revocations: [DeviceRevocation],
            grants: [EpochGrant], requests: [RepairRequest] = [], answers: [RepairAnswer] = [],
            identities: [IdentityPublicKeys] = [], notifyWalls: [ParticipantID]? = nil,
            confirmations: [JoinConfirmedBody] = []
        ) {
            self.entries = entries
            self.identities = identities
            self.certificates = certificates
            self.revocations = revocations
            self.grants = grants
            self.requests = requests
            self.answers = answers
            self.notifyWalls = notifyWalls
            self.confirmations = confirmations
        }
    }

    private struct Body: Codable {
        var entries: [Entry] = []
        var identities: [IdentityPublicKeys] = []
        var certificates: [DeviceCertificate] = []
        var revocations: [DeviceRevocation] = []
        var requests: [RepairRequest] = []
        var answers: [RepairAnswer] = []
        var notifyWalls: [ParticipantID]?
        var confirmations: [JoinConfirmedBody] = []

        init(
            entries: [Entry] = [], certificates: [DeviceCertificate] = [],
            revocations: [DeviceRevocation] = [], requests: [RepairRequest] = [],
            answers: [RepairAnswer] = [], identities: [IdentityPublicKeys] = [],
            notifyWalls: [ParticipantID]? = nil, confirmations: [JoinConfirmedBody] = []
        ) {
            self.entries = entries
            self.identities = identities
            self.certificates = certificates
            self.revocations = revocations
            self.requests = requests
            self.answers = answers
            self.notifyWalls = notifyWalls
            self.confirmations = confirmations
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
            identities =
                try container.decodeIfPresent([IdentityPublicKeys].self, forKey: .identities) ?? []
            certificates =
                try container.decodeIfPresent([DeviceCertificate].self, forKey: .certificates) ?? []
            revocations =
                try container.decodeIfPresent([DeviceRevocation].self, forKey: .revocations) ?? []
            requests = try container.decodeIfPresent([RepairRequest].self, forKey: .requests) ?? []
            answers = try container.decodeIfPresent([RepairAnswer].self, forKey: .answers) ?? []
            notifyWalls = try container.decodeIfPresent([ParticipantID].self, forKey: .notifyWalls)
            confirmations =
                try container.decodeIfPresent([JoinConfirmedBody].self, forKey: .confirmations) ?? []
        }
    }

    public static func pack(
        _ entries: [Entry],
        for peers: [Peer],
        certificates: [DeviceCertificate] = [],
        revocations: [DeviceRevocation] = [],
        granting: [(to: Peer, grant: EpochGrant)] = [],
        window: UInt64,
        id: PacketID = PacketID(),
        requests: [RepairRequest] = [],
        answers: [RepairAnswer] = [],
        identities: [IdentityPublicKeys] = [],
        notifyWalls: [ParticipantID]? = nil,
        confirmations: [JoinConfirmedBody] = []
    ) throws -> SyncPacket {
        let contentKey = SymmetricKey(size: .bits256)
        let context = wrapContext(id: id)

        let body = Body(
            entries: entries, certificates: certificates, revocations: revocations,
            requests: requests, answers: answers, identities: identities,
            notifyWalls: notifyWalls, confirmations: confirmations)
        let sealed = try ChaChaPoly.seal(
            try JSONEncoder().encode(body), using: contentKey, authenticating: context)

        var wraps: [RecipientTag: Data] = [:]
        for peer in peers {
            let material = contentKey.withUnsafeBytes { Data($0) }
            wraps[peer.outgoingTag(window: window)] = try peer.secret.wrap(
                material, context: context)
        }

        var addressed: [RecipientTag: [Data]] = [:]
        for issued in granting {
            addressed[issued.to.outgoingTag(window: window), default: []].append(
                try JSONEncoder().encode(issued.grant))
        }

        return SyncPacket(
            id: id, wraps: wraps, ciphertext: sealed.combined, grants: addressed)
    }

    public static func unpack(
        _ packet: SyncPacket, as peer: Peer, window: UInt64
    ) throws -> Delivery {
        let tag = peer.incomingTag(window: window)
        guard let wrap = packet.wraps[tag] else { throw SyncError.notAddressedToUs }

        let context = wrapContext(id: packet.id)
        let material = try peer.secret.unwrap(wrap, context: context)

        guard let box = try? ChaChaPoly.SealedBox(combined: packet.ciphertext),
            let plaintext = try? ChaChaPoly.open(
                box, using: SymmetricKey(data: material), authenticating: context)
        else {
            throw SyncError.packetUnreadable
        }

        let grants = (packet.grants[tag] ?? []).compactMap {
            try? JSONDecoder().decode(EpochGrant.self, from: $0)
        }

        let body = try JSONDecoder().decode(Body.self, from: plaintext)
        return Delivery(
            entries: body.entries, certificates: body.certificates,
            revocations: body.revocations, grants: grants, requests: body.requests,
            answers: body.answers, identities: body.identities, notifyWalls: body.notifyWalls,
            confirmations: body.confirmations)
    }

    private static func wrapContext(id: PacketID) -> Data {
        CanonicalBytes.payload(
            domain: Domain.syncPacket,
            fields: [withUnsafeBytes(of: id.rawValue.uuid) { Data($0) }]
        )
    }
}
