import CryptoKit
import Foundation

public struct DeviceRecipient: Hashable, Sendable {
    public let device: DeviceID
    public let sealingKey: Data

    public init(device: DeviceID, sealingKey: Data) {
        self.device = device
        self.sealingKey = sealingKey
    }
}

public struct DeviceSeal: Hashable, Sendable, Codable {
    public let device: DeviceID
    public let encapsulated: Data
    public let sealed: Data

    public static let encapsulatedByteCount = 1_120

    public static func seal(_ plaintext: Data, to recipient: DeviceRecipient, context: Data) throws -> DeviceSeal {
        var sender = try HPKE.Sender(
            recipientKey: try XWingMLKEM768X25519.PublicKey(rawRepresentation: recipient.sealingKey),
            ciphersuite: suite, info: info(device: recipient.device, context: context))
        let sealed = try sender.seal(plaintext)
        return DeviceSeal(device: recipient.device, encapsulated: sender.encapsulatedKey, sealed: sealed)
    }

    public func open(with device: DeviceKeys, context: Data) throws -> Data {
        guard device.id == self.device,
            var recipient = try? HPKE.Recipient(
                privateKey: device.sealingKey, ciphersuite: Self.suite,
                info: Self.info(device: self.device, context: context), encapsulatedKey: encapsulated),
            let plaintext = try? recipient.open(sealed)
        else { throw CryptoError.openFailed }
        return plaintext
    }

    private static let suite = HPKE.Ciphersuite.XWingMLKEM768X25519_SHA256_AES_GCM_256

    private static func info(device: DeviceID, context: Data) -> Data {
        CanonicalBytes.payload(domain: Domain.deviceSeal, fields: [device.rawValue, context])
    }

    init(device: DeviceID, encapsulated: Data, sealed: Data) {
        self.device = device
        self.encapsulated = encapsulated
        self.sealed = sealed
    }

    private enum CodingKeys: String, CodingKey {
        case device, encapsulated, sealed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        device = try container.decode(DeviceID.self, forKey: .device)
        encapsulated = try container.decode(Data.self, forKey: .encapsulated)
        sealed = try container.decode(Data.self, forKey: .sealed)
        guard encapsulated.count == Self.encapsulatedByteCount, sealed.count <= MailboxRules.recordByteCeiling
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .sealed, in: container, debugDescription: "a device seal of the wrong size")
        }
    }
}
