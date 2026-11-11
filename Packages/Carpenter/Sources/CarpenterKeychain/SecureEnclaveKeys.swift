import CarpenterKit
import CryptoKit
import Foundation
import LocalAuthentication
import OSLog
import Security

public struct SecureEnclaveKeys: HardwareKeys {
    private let service: String

    public init(service: String) {
        self.service = service
    }

    public static var isAvailable: Bool { SecureEnclave.isAvailable }

    public func make(_ id: HardwareKeyID, opensFor rule: HardwareKeyRule) async throws -> Data {
        guard Self.isAvailable else { throw HardwareKeyError.unavailable }
        var error: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, Self.flags(for: rule), &error)
        else { throw Self.failure(error, making: true) }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag(id),
                kSecAttrLabel as String: service,
                kSecAttrAccessControl as String: control,
            ],
        ]
        var made: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &made) else {
            throw Self.failure(made, making: true)
        }
        guard let publicKey = SecKeyCopyPublicKey(key),
            let bytes = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        else { throw HardwareKeyError.unavailable }
        return bytes
    }

    public func agree(_ id: HardwareKeyID, with publicKey: Data, reason: String) async throws -> Data {
        let key = try find(id, reason: reason)
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
        else { throw Self.failure(error, making: false) }
        return shared
    }

    public func remove(_ id: HardwareKeyID) async throws {
        SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag(id),
        ] as CFDictionary)
    }

    private static func flags(for rule: HardwareKeyRule) -> SecAccessControlCreateFlags {
        switch rule {
        case .unlockedPhone: [.privateKeyUsage]
        case .ownerPresent: [.privateKeyUsage, .userPresence]
        case .enrolledFaces: [.privateKeyUsage, .biometryCurrentSet]
        }
    }

    private static func failure(_ error: Unmanaged<CFError>?, making: Bool) -> HardwareKeyError {
        let failure = error?.takeRetainedValue() as Error? as NSError?
        let (domain, code) = (failure?.domain ?? "none", failure?.code ?? 0)
        Diagnostics.identity.error(
            "secure enclave: \(making ? "making" : "using", privacy: .public) a key failed: \(domain, privacy: .public) \(code, privacy: .public)"
        )
        switch (domain, code) {
        case (LAError.errorDomain, LAError.Code.passcodeNotSet.rawValue): return .noPasscode
        case (NSOSStatusErrorDomain, Int(errSecItemNotFound)): return .noSuchKey
        case (NSOSStatusErrorDomain, Int(errSecInteractionNotAllowed)): return .locked
        default: return making ? .unavailable : .refused
        }
    }

    private func find(_ id: HardwareKeyID, reason: String) throws -> SecKey {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag(id),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        if !reason.isEmpty {
            let context = LAContext()
            context.localizedReason = reason
            if id.purpose == .biometrics { context.localizedFallbackTitle = "" }
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let item, CFGetTypeID(item) == SecKeyGetTypeID() else { throw HardwareKeyError.unavailable }
            return item as! SecKey
        case errSecItemNotFound: throw HardwareKeyError.noSuchKey
        case errSecInteractionNotAllowed: throw HardwareKeyError.locked
        default:
            Diagnostics.identity.error("secure enclave: finding a key failed: \(status, privacy: .public)")
            throw HardwareKeyError.refused
        }
    }

    private func tag(_ id: HardwareKeyID) -> Data {
        Data("\(service).\(id.rawValue)".utf8)
    }
}
