import CryptoKit
import Foundation

public struct DeviceRecipient: Hashable, Sendable {
    public let device: DeviceID
    public let agreementKey: Data

    public init(device: DeviceID, agreementKey: Data) {
        self.device = device
        self.agreementKey = agreementKey
    }
}

public struct DeviceSeal: Hashable, Sendable, Codable {
    public let device: DeviceID
    public let ephemeral: Data
    public let sealed: Data

    public static func seal(_ plaintext: Data, to recipient: DeviceRecipient, context: Data) throws -> DeviceSeal {
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let theirs = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipient.agreementKey)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: theirs)
        let ephemeralPublic = ephemeral.publicKey.rawRepresentation
        let box = try ChaChaPoly.seal(
            plaintext,
            using: key(shared, device: recipient.device, ephemeral: ephemeralPublic, context: context),
            authenticating: context)
        return DeviceSeal(device: recipient.device, ephemeral: ephemeralPublic, sealed: box.combined)
    }

    public func open(with device: DeviceKeys, context: Data) throws -> Data {
        guard device.id == self.device,
            let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeral),
            let shared = try? device.agreementKey.sharedSecretFromKeyAgreement(with: theirs),
            let box = try? ChaChaPoly.SealedBox(combined: sealed),
            let plaintext = try? ChaChaPoly.open(
                box, using: Self.key(shared, device: self.device, ephemeral: ephemeral, context: context),
                authenticating: context)
        else { throw CryptoError.openFailed }
        return plaintext
    }

    private static func key(_ shared: SharedSecret, device: DeviceID, ephemeral: Data, context: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(Domain.deviceSeal.utf8),
            sharedInfo: CanonicalBytes.payload(
                domain: Domain.deviceSeal, fields: [device.rawValue, ephemeral, context]),
            outputByteCount: 32)
    }
}
