import CryptoKit
import Foundation

public struct DeviceRequest: Hashable, Sendable, Codable {
    public let devicePublicKey: Data
    public let agreementKey: Data

    public init(devicePublicKey: Data, agreementKey: Data) {
        self.devicePublicKey = devicePublicKey
        self.agreementKey = agreementKey
    }

    public init(for device: DeviceKeys) {
        self.init(devicePublicKey: device.publicKey, agreementKey: device.agreementPublicKey)
    }

    public var device: DeviceID { DeviceID(publicKey: devicePublicKey) }

    public var code: String {
        let transcript = CanonicalBytes.payload(
            domain: Domain.deviceApprovalCode, fields: [devicePublicKey, agreementKey])
        var code = ""
        var block = UInt64(0)
        while code.count < Self.codeLength {
            let digest = SHA256.hash(data: transcript + CanonicalBytes.sequence(block))
            for byte in digest where Int(byte) < ShortAuthenticationString.ceiling {
                code.append(
                    ShortAuthenticationString.alphabet[
                        Int(byte) % ShortAuthenticationString.alphabet.count])
                if code.count == Self.codeLength { break }
            }
            block += 1
        }
        return code
    }

    public static let codeLength = 6

    public func record() throws -> SiblingRecord {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return SiblingRecord(
            name: SiblingRecord.Name(writer: device, kind: .request),
            sealed: SealedSiblingFeed(ciphertext: try encoder.encode(self)))
    }

    public init?(record: SiblingRecord) {
        guard case .request = record.name.kind,
            let decoded = try? JSONDecoder().decode(DeviceRequest.self, from: record.sealed.ciphertext),
            decoded.device == record.name.writer,
            (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: decoded.agreementKey)) != nil
        else { return nil }
        self = decoded
    }
}

public struct DeviceApproval: Hashable, Sendable, Codable {
    public let signingSeed: Data
    public let agreementSeed: Data
    public let certificates: [DeviceCertificate]
    public let revocations: [DeviceRevocation]

    public init(
        identity: Identity, certificates: [DeviceCertificate], revocations: [DeviceRevocation]
    ) {
        signingSeed = identity.signingSeed
        agreementSeed = identity.agreementSeed
        self.certificates = certificates
        self.revocations = revocations
    }

    public func identity() throws -> Identity {
        try Identity(signingSeed: signingSeed, agreementSeed: agreementSeed)
    }

    private static func context(approver: DeviceID, request: DeviceRequest) -> Data {
        CanonicalBytes.payload(
            domain: Domain.deviceApproval,
            fields: [approver.rawValue, request.devicePublicKey, request.agreementKey])
    }

    public func record(from approver: DeviceID, to request: DeviceRequest) throws -> SiblingRecord {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let seal = try DeviceSeal.seal(
            try encoder.encode(self),
            to: DeviceRecipient(device: request.device, agreementKey: request.agreementKey),
            context: Self.context(approver: approver, request: request))
        return SiblingRecord(
            name: SiblingRecord.Name(writer: approver, kind: .approval(for: request.device)),
            sealed: SealedSiblingFeed(ciphertext: try encoder.encode(seal)))
    }

    public init(record: SiblingRecord, opening device: DeviceKeys) throws {
        guard case .approval(let target) = record.name.kind, target == device.id,
            let seal = try? JSONDecoder().decode(DeviceSeal.self, from: record.sealed.ciphertext)
        else { throw CryptoError.openFailed }
        let plaintext = try seal.open(
            with: device,
            context: Self.context(approver: record.name.writer, request: DeviceRequest(for: device)))
        self = try JSONDecoder().decode(DeviceApproval.self, from: plaintext)
    }
}
