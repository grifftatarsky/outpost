import CarpenterKit
import CryptoKit
import Foundation
import LocalAuthentication
import Security

public struct SecureEnclaveKeys: HardwareKeys {
    private let service: String

    public init(service: String) {
        self.service = service
    }

    public static var isAvailable: Bool { SecureEnclave.isAvailable }

    public func make(_ id: HardwareKeyID, requiringBiometrics: Bool) async throws -> Data {
        guard Self.isAvailable else { throw HardwareKeyError.unavailable }
        try? await remove(id)
        var error: Unmanaged<CFError>?
        let flags: SecAccessControlCreateFlags =
            requiringBiometrics ? [.privateKeyUsage, .biometryCurrentSet] : [.privateKeyUsage]
        guard let control = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &error)
        else { throw HardwareKeyError.unavailable }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag(id),
                kSecAttrAccessControl as String: control,
            ],
        ]
        var made: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &made) else {
            throw HardwareKeyError.unavailable
        }
        guard let publicKey = SecKeyCopyPublicKey(key),
            let bytes = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        else { throw HardwareKeyError.unavailable }
        return bytes
    }

    public func publicKey(of id: HardwareKeyID) async throws -> Data? {
        guard let key = find(id, reason: nil), let publicKey = SecKeyCopyPublicKey(key) else { return nil }
        return SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
    }

    public func agree(_ id: HardwareKeyID, with publicKey: Data, reason: String) async throws -> Data {
        guard let key = find(id, reason: reason.isEmpty ? nil : reason) else { throw HardwareKeyError.noSuchKey }
        let theirs = try P256.KeyAgreement.PublicKey(x963Representation: publicKey)
        guard let peer = SecKeyCreateWithData(
            theirs.x963Representation as CFData,
            [
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
                kSecAttrKeySizeInBits as String: 256,
            ] as CFDictionary, nil)
        else { throw HardwareKeyError.unavailable }

        var error: Unmanaged<CFError>?
        guard let shared = SecKeyCopyKeyExchangeResult(
            key, .ecdhKeyExchangeStandard, peer, [:] as CFDictionary, &error) as Data?
        else { throw HardwareKeyError.refused }
        return shared
    }

    public func remove(_ id: HardwareKeyID) async throws {
        SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag(id),
        ] as CFDictionary)
    }

    private func find(_ id: HardwareKeyID, reason: String?) -> SecKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag(id),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        if let reason {
            let context = LAContext()
            context.localizedReason = reason
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return (item as! SecKey?)
    }

    private func tag(_ id: HardwareKeyID) -> Data {
        Data("\(service).\(id.rawValue)".utf8)
    }
}
