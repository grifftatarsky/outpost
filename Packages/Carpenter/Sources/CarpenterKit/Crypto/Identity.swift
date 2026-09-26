import CryptoKit
import Foundation

public struct ParticipantID: Hashable, Sendable, Codable {
    public static let width = SHA256.byteCount

    public let rawValue: Data

    public init(rawValue: Data) {
        self.rawValue = rawValue
    }

    private enum CodingKeys: String, CodingKey { case rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(Data.self, forKey: .rawValue)
        guard raw.count == Self.width else {
            throw DecodingError.dataCorruptedError(
                forKey: .rawValue, in: container,
                debugDescription: IdentityWidth.reason("a participant", raw.count))
        }
        rawValue = raw
    }
}

public struct DeviceID: Hashable, Sendable, Codable {
    public static let width = SHA256.byteCount

    public let rawValue: Data

    public init(rawValue: Data) {
        self.rawValue = rawValue
    }

    public init(publicKey: Data) {
        let digest = SHA256.hash(
            data: CanonicalBytes.payload(domain: Domain.deviceID, fields: [publicKey]))
        self.init(rawValue: Data(digest))
    }

    private enum CodingKeys: String, CodingKey { case rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(Data.self, forKey: .rawValue)
        guard raw.count == Self.width else {
            throw DecodingError.dataCorruptedError(
                forKey: .rawValue, in: container,
                debugDescription: IdentityWidth.reason("a device", raw.count))
        }
        rawValue = raw
    }
}

enum IdentityWidth {
    static func reason(_ what: String, _ found: Int) -> String {
        """
        \(what) identifier arrived \(found) bytes wide rather than 32. Both identifiers are SHA256 \
        digests, and `FeedKey.canonicalBytes` concatenates them without length prefixes, so a \
        different width would make two different feeds encode to the same bytes — in the vector \
        clock a signature is taken over, and in the associated data a payload is sealed against. \
        The fixed width is the invariant that makes that concatenation safe, and this is where it \
        is enforced, because decoding is where bytes this process did not write come in.
        """
    }
}

public struct IdentityPublicKeys: Hashable, Sendable, Codable {
    public let signing: Data
    public let agreement: Data

    public init(signing: Data, agreement: Data) {
        self.signing = signing
        self.agreement = agreement
    }

    public var participantID: ParticipantID {
        let digest = SHA256.hash(
            data: CanonicalBytes.payload(domain: Domain.participantID, fields: [signing, agreement]))
        return ParticipantID(rawValue: Data(digest))
    }

    public func isValidSignature(_ signature: Data, for message: Data) throws -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: signing) else {
            throw CryptoError.malformedKey
        }
        return key.isValidSignature(signature, for: message)
    }
}

public struct Identity: Hashable, Sendable {
    public let signingSeed: Data
    public let agreementSeed: Data
    public let publicKeys: IdentityPublicKeys
    public let id: ParticipantID

    public init(signingSeed: Data, agreementSeed: Data) throws {
        guard let signing = try? Curve25519.Signing.PrivateKey(rawRepresentation: signingSeed),
            let agreement = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: agreementSeed)
        else {
            throw CryptoError.malformedKey
        }
        self.init(signing: signing, agreement: agreement)
    }

    public static func generate() -> Identity {
        Identity(signing: Curve25519.Signing.PrivateKey(), agreement: Curve25519.KeyAgreement.PrivateKey())
    }

    private init(signing: Curve25519.Signing.PrivateKey, agreement: Curve25519.KeyAgreement.PrivateKey) {
        signingSeed = signing.rawRepresentation
        agreementSeed = agreement.rawRepresentation
        publicKeys = IdentityPublicKeys(
            signing: signing.publicKey.rawRepresentation,
            agreement: agreement.publicKey.rawRepresentation)
        id = publicKeys.participantID
    }

    public func sign(_ message: Data) throws -> Data {
        try signingKey.signature(for: message)
    }

    public func sharedSecret(with peer: IdentityPublicKeys) throws -> SharedSecret {
        guard let peerKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peer.agreement)
        else {
            throw CryptoError.malformedKey
        }
        return try agreementKey.sharedSecretFromKeyAgreement(with: peerKey)
    }

    private var signingKey: Curve25519.Signing.PrivateKey {
        try! Curve25519.Signing.PrivateKey(rawRepresentation: signingSeed)
    }

    private var agreementKey: Curve25519.KeyAgreement.PrivateKey {
        try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: agreementSeed)
    }
}

public struct DeviceKeys: Hashable, Sendable {
    public let signingSeed: Data
    public let publicKey: Data
    public let id: DeviceID

    public init(signingSeed: Data) throws {
        guard let signing = try? Curve25519.Signing.PrivateKey(rawRepresentation: signingSeed) else {
            throw CryptoError.malformedKey
        }
        self.init(signing: signing)
    }

    public static func generate() -> DeviceKeys {
        DeviceKeys(signing: Curve25519.Signing.PrivateKey())
    }

    private init(signing: Curve25519.Signing.PrivateKey) {
        signingSeed = signing.rawRepresentation
        publicKey = signing.publicKey.rawRepresentation
        id = DeviceID(publicKey: publicKey)
    }

    public func sign(_ message: Data) throws -> Data {
        try signingKey.signature(for: message)
    }

    public static func isValidSignature(
        _ signature: Data, for message: Data, publicKey: Data
    ) throws -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            throw CryptoError.malformedKey
        }
        return key.isValidSignature(signature, for: message)
    }

    private var signingKey: Curve25519.Signing.PrivateKey {
        try! Curve25519.Signing.PrivateKey(rawRepresentation: signingSeed)
    }
}

enum Domain {
    static let participantID = "carpenter.participant-id.v1"
    static let deviceID = "carpenter.device-id.v1"
    static let deviceCertificate = "carpenter.device-certificate.v1"
    static let deviceRevocation = "carpenter.device-revocation.v1"
    static let verificationPhrase = "carpenter.verification-phrase.v1"
    static let comparisonCode = "carpenter.comparison-code.v1"

    static let joinConfirmed = "carpenter.join-confirmed.v1"
    static let joinCommitment = "carpenter.join-commitment.v1"
    static let joinerCode = "carpenter.joiner-code.v1"

    static let siblingFeed = "carpenter.sibling-feed.v1"
    static let vectorClock = "carpenter.vector-clock.v1"
    static let payload = "carpenter.payload.v1"
    static let entry = "carpenter.entry.v1"
    static let entryHash = "carpenter.entry-hash.v1"
    static let pairwiseSecret = "carpenter.pairwise-secret.v1"
    static let recipientTag = "carpenter.recipient-tag.v1"
    static let messageBell = "carpenter.message-bell.v1"
    static let shareOffer = "carpenter.share-offer.v1"
    static let shareOfferDigest = "carpenter.share-offer-digest.v1"
    static let epochLink = "carpenter.epoch-link.v1"
    static let epochWrapping = "carpenter.epoch-wrapping.v1"
    static let epochSealing = "carpenter.epoch-sealing.v1"
    static let epochGrant = "carpenter.epoch-grant.v1"
    static let sealedPayload = "carpenter.sealed-payload.v1"
    static let syncPacket = "carpenter.sync-packet.v1"
    static let attachment = "carpenter.attachment.v1"
    static let membershipAttestation = "carpenter.membership-attestation.v1"
}
