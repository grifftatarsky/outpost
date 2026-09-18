import Foundation

public struct DeviceCertificate: Hashable, Sendable, Codable {
    public var participant: ParticipantID
    public var device: DeviceID
    public var devicePublicKey: Data
    public var issuedAt: Date
    public var signature: Data

    public init(
        participant: ParticipantID,
        device: DeviceID,
        devicePublicKey: Data,
        issuedAt: Date,
        signature: Data
    ) {
        self.participant = participant
        self.device = device
        self.devicePublicKey = devicePublicKey
        self.issuedAt = issuedAt
        self.signature = signature
    }

    public static func issue(
        for devicePublicKey: Data, by identity: Identity, at issuedAt: Date
    ) throws -> DeviceCertificate {
        var certificate = DeviceCertificate(
            participant: identity.id,
            device: DeviceID(publicKey: devicePublicKey),
            devicePublicKey: devicePublicKey,
            issuedAt: issuedAt,
            signature: Data()
        )
        certificate.signature = try identity.sign(certificate.signingPayload)
        return certificate
    }

    var signingPayload: Data {
        CanonicalBytes.payload(
            domain: Domain.deviceCertificate,
            fields: [
                participant.rawValue,
                device.rawValue,
                devicePublicKey,
                CanonicalBytes.timestamp(issuedAt),
            ]
        )
    }

    public func verify(against identityKeys: IdentityPublicKeys) throws {
        guard participant == identityKeys.participantID else {
            throw CryptoError.participantMismatch
        }
        guard device == DeviceID(publicKey: devicePublicKey) else {
            throw CryptoError.deviceMismatch
        }
        guard try identityKeys.isValidSignature(signature, for: signingPayload) else {
            throw CryptoError.badSignature
        }
    }
}

public struct DeviceRevocation: Hashable, Sendable, Codable {
    public var participant: ParticipantID
    public var device: DeviceID
    public var revokedAt: Date
    public var signature: Data

    public init(
        participant: ParticipantID,
        device: DeviceID,
        revokedAt: Date,
        signature: Data
    ) {
        self.participant = participant
        self.device = device
        self.revokedAt = revokedAt
        self.signature = signature
    }

    public static func issue(
        for device: DeviceID, by identity: Identity, at revokedAt: Date
    ) throws -> DeviceRevocation {
        var revocation = DeviceRevocation(
            participant: identity.id,
            device: device,
            revokedAt: revokedAt,
            signature: Data()
        )
        revocation.signature = try identity.sign(revocation.signingPayload)
        return revocation
    }

    var signingPayload: Data {
        CanonicalBytes.payload(
            domain: Domain.deviceRevocation,
            fields: [
                participant.rawValue,
                device.rawValue,
                CanonicalBytes.timestamp(revokedAt),
            ]
        )
    }

    public func verify(against identityKeys: IdentityPublicKeys) throws {
        guard participant == identityKeys.participantID else {
            throw CryptoError.participantMismatch
        }
        guard try identityKeys.isValidSignature(signature, for: signingPayload) else {
            throw CryptoError.badSignature
        }
    }
}
