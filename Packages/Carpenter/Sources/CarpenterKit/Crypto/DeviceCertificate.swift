import CryptoKit
import Foundation

public struct DeviceCertificate: Hashable, Sendable, Codable {
    public var participant: ParticipantID
    public var device: DeviceID
    public var devicePublicKey: Data
    public var issuedAt: Date
    public var signature: Data
    public var agreementKey: Data?
    public var approvedBy: DeviceID?
    public var approval: Data?
    public var recoverySignature: Data?

    public init(
        participant: ParticipantID,
        device: DeviceID,
        devicePublicKey: Data,
        issuedAt: Date,
        signature: Data,
        agreementKey: Data? = nil,
        approvedBy: DeviceID? = nil,
        approval: Data? = nil,
        recoverySignature: Data? = nil
    ) {
        self.participant = participant
        self.device = device
        self.devicePublicKey = devicePublicKey
        self.issuedAt = issuedAt
        self.signature = signature
        self.agreementKey = agreementKey
        self.approvedBy = approvedBy
        self.approval = approval
        self.recoverySignature = recoverySignature
    }

    public static func issue(
        for devicePublicKey: Data, agreementKey: Data? = nil, by identity: Identity, at issuedAt: Date,
        approvedBy approver: DeviceKeys? = nil
    ) throws -> DeviceCertificate {
        var certificate = DeviceCertificate(
            participant: identity.id,
            device: DeviceID(publicKey: devicePublicKey),
            devicePublicKey: devicePublicKey,
            issuedAt: issuedAt,
            signature: Data(),
            agreementKey: agreementKey,
            approvedBy: approver?.id
        )
        certificate.signature = try identity.sign(certificate.signingPayload)
        if let approver {
            certificate.approval = try approver.sign(certificate.signingPayload)
        }
        return certificate
    }

    public static func issue(
        for device: DeviceKeys, by identity: Identity, at issuedAt: Date,
        approvedBy approver: DeviceKeys? = nil
    ) throws -> DeviceCertificate {
        try issue(
            for: device.publicKey, agreementKey: device.agreementPublicKey, by: identity, at: issuedAt,
            approvedBy: approver)
    }

    public static func recovered(
        for device: DeviceKeys, by identity: Identity, at issuedAt: Date
    ) throws -> DeviceCertificate {
        try recovered(
            for: device.publicKey, agreementKey: device.agreementPublicKey, by: identity, at: issuedAt)
    }

    public static func recovered(
        for devicePublicKey: Data, agreementKey: Data? = nil, by identity: Identity, at issuedAt: Date
    ) throws -> DeviceCertificate {
        guard let recovery = identity.recovery else { throw CryptoError.notAuthorized }
        var certificate = DeviceCertificate(
            participant: identity.id,
            device: DeviceID(publicKey: devicePublicKey),
            devicePublicKey: devicePublicKey,
            issuedAt: issuedAt,
            signature: Data(),
            agreementKey: agreementKey,
            recoverySignature: Data()
        )
        certificate.signature = try identity.sign(certificate.signingPayload)
        certificate.recoverySignature = try recovery.sign(certificate.signingPayload)
        return certificate
    }

    public var isRecovery: Bool { recoverySignature != nil }

    var signingPayload: Data {
        var fields = [
            participant.rawValue,
            device.rawValue,
            devicePublicKey,
            CanonicalBytes.timestamp(issuedAt),
        ]
        if let agreementKey { fields += [Data("agreement-key".utf8), agreementKey] }
        if let approvedBy { fields += [Data("approved-by".utf8), approvedBy.rawValue] }
        if recoverySignature != nil { fields += [Data(Domain.recoveryReset.utf8)] }
        return CanonicalBytes.payload(domain: Domain.deviceCertificate, fields: fields)
    }

    public func verify(against identityKeys: IdentityPublicKeys) throws {
        guard participant == identityKeys.participantID else {
            throw CryptoError.participantMismatch
        }
        guard device == DeviceID(publicKey: devicePublicKey) else {
            throw CryptoError.deviceMismatch
        }
        guard (approvedBy == nil) == (approval == nil) else {
            throw CryptoError.badSignature
        }
        guard approvedBy == nil || recoverySignature == nil else {
            throw CryptoError.badSignature
        }
        guard try identityKeys.isValidSignature(signature, for: signingPayload) else {
            throw CryptoError.badSignature
        }
        if let recoverySignature {
            guard identityKeys.isValidRecoverySignature(recoverySignature, for: signingPayload) else {
                throw CryptoError.badSignature
            }
        }
    }

    public var digest: Data {
        var fields = [Data("certificate".utf8), signingPayload, signature, approval ?? Data()]
        if let recoverySignature { fields.append(recoverySignature) }
        return Data(
            SHA256.hash(data: CanonicalBytes.payload(domain: Domain.authorityRecord, fields: fields)))
    }

    func isApproved(byKey approverPublicKey: Data) -> Bool {
        guard let approval else { return false }
        return (try? DeviceKeys.isValidSignature(approval, for: signingPayload, publicKey: approverPublicKey))
            == true
    }
}

public struct DeviceRevocation: Hashable, Sendable, Codable {
    public var participant: ParticipantID
    public var device: DeviceID
    public var revokedAt: Date
    public var signature: Data
    public var revokedBy: DeviceID?
    public var revokerSignature: Data?
    public var cutoff: UInt64?

    public init(
        participant: ParticipantID,
        device: DeviceID,
        revokedAt: Date,
        signature: Data,
        revokedBy: DeviceID? = nil,
        revokerSignature: Data? = nil,
        cutoff: UInt64? = nil
    ) {
        self.participant = participant
        self.device = device
        self.revokedAt = revokedAt
        self.signature = signature
        self.revokedBy = revokedBy
        self.revokerSignature = revokerSignature
        self.cutoff = cutoff
    }

    public static func issue(
        for device: DeviceID, by identity: Identity, at revokedAt: Date,
        from revoker: DeviceKeys? = nil, cutoff: UInt64? = nil
    ) throws -> DeviceRevocation {
        var revocation = DeviceRevocation(
            participant: identity.id,
            device: device,
            revokedAt: revokedAt,
            signature: Data(),
            revokedBy: revoker?.id,
            cutoff: cutoff
        )
        revocation.signature = try identity.sign(revocation.signingPayload)
        if let revoker {
            revocation.revokerSignature = try revoker.sign(revocation.signingPayload)
        }
        return revocation
    }

    var signingPayload: Data {
        var fields = [
            participant.rawValue,
            device.rawValue,
            CanonicalBytes.timestamp(revokedAt),
        ]
        if let revokedBy { fields += [Data("revoked-by".utf8), revokedBy.rawValue] }
        if let cutoff { fields += [Data("cutoff".utf8), CanonicalBytes.sequence(cutoff)] }
        return CanonicalBytes.payload(domain: Domain.deviceRevocation, fields: fields)
    }

    public func verify(against identityKeys: IdentityPublicKeys) throws {
        guard participant == identityKeys.participantID else {
            throw CryptoError.participantMismatch
        }
        guard (revokedBy == nil) == (revokerSignature == nil) else {
            throw CryptoError.badSignature
        }
        guard try identityKeys.isValidSignature(signature, for: signingPayload) else {
            throw CryptoError.badSignature
        }
    }

    public var digest: Data {
        Data(
            SHA256.hash(
                data: CanonicalBytes.payload(
                    domain: Domain.authorityRecord,
                    fields: [Data("revocation".utf8), signingPayload, signature, revokerSignature ?? Data()])))
    }

    func isSigned(byKey revokerPublicKey: Data) -> Bool {
        guard let revokerSignature else { return false }
        return (try? DeviceKeys.isValidSignature(
            revokerSignature, for: signingPayload, publicKey: revokerPublicKey)) == true
    }
}
