import CommonCrypto
import CryptoKit
import Foundation

public struct HardwareKeyID: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let code = HardwareKeyID(rawValue: "vault.code")
    public static let biometrics = HardwareKeyID(rawValue: "vault.biometrics")
}

public enum HardwareKeyError: Error, Hashable, Sendable {
    case unavailable
    case refused
    case noSuchKey
}

public protocol HardwareKeys: Sendable {
    func make(_ id: HardwareKeyID, requiringBiometrics: Bool) async throws -> Data
    func publicKey(of id: HardwareKeyID) async throws -> Data?
    func agree(_ id: HardwareKeyID, with publicKey: Data, reason: String) async throws -> Data
    func remove(_ id: HardwareKeyID) async throws
}

public struct SealedVaultKey: Hashable, Sendable, Codable {
    public struct Wrapping: Hashable, Sendable, Codable {
        public let ephemeral: Data
        public let sealed: Data

        public init(ephemeral: Data, sealed: Data) {
            self.ephemeral = ephemeral
            self.sealed = sealed
        }
    }

    public let salt: Data
    public let rounds: Int
    public let byCode: Wrapping
    public let byBiometrics: Wrapping?

    public init(salt: Data, rounds: Int, byCode: Wrapping, byBiometrics: Wrapping?) {
        self.salt = salt
        self.rounds = rounds
        self.byCode = byCode
        self.byBiometrics = byBiometrics
    }

    public var usesBiometrics: Bool { byBiometrics != nil }

    public static let key = KeychainKey("vault.key")
}

public enum VaultError: Error, Hashable, Sendable {
    case wrongCode
    case biometricsNotSet
    case shut
}

public enum Vault {
    public static let rounds = 300_000

    public static func create(
        code: String, usingBiometrics: Bool, hardware: any HardwareKeys, rounds: Int = Vault.rounds
    ) async throws -> (key: SymmetricKey, sealed: SealedVaultKey) {
        let vaultKey = SymmetricKey(size: .bits256)
        let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        _ = try await hardware.make(.code, requiringBiometrics: false)
        let byCode = try await wrap(vaultKey, with: .code, code: code, salt: salt, rounds: rounds, hardware: hardware)
        var byBiometrics: SealedVaultKey.Wrapping?
        if usingBiometrics {
            _ = try await hardware.make(.biometrics, requiringBiometrics: true)
            byBiometrics = try await wrap(
                vaultKey, with: .biometrics, code: nil, salt: salt, rounds: rounds, hardware: hardware)
        }
        return (
            vaultKey,
            SealedVaultKey(salt: salt, rounds: rounds, byCode: byCode, byBiometrics: byBiometrics)
        )
    }

    public static func open(
        _ sealed: SealedVaultKey, with code: String, hardware: any HardwareKeys, reason: String
    ) async throws -> SymmetricKey {
        let wrapping = try await wrappingKey(
            .code, code: code, salt: sealed.salt, rounds: sealed.rounds, ephemeral: sealed.byCode.ephemeral,
            hardware: hardware, reason: reason)
        guard let box = try? ChaChaPoly.SealedBox(combined: sealed.byCode.sealed),
            let opened = try? ChaChaPoly.open(box, using: wrapping, authenticating: context(.code))
        else { throw VaultError.wrongCode }
        return SymmetricKey(data: opened)
    }

    public static func openWithBiometrics(
        _ sealed: SealedVaultKey, hardware: any HardwareKeys, reason: String
    ) async throws -> SymmetricKey {
        guard let byBiometrics = sealed.byBiometrics else { throw VaultError.biometricsNotSet }
        let wrapping = try await wrappingKey(
            .biometrics, code: nil, salt: sealed.salt, rounds: sealed.rounds, ephemeral: byBiometrics.ephemeral,
            hardware: hardware, reason: reason)
        guard let box = try? ChaChaPoly.SealedBox(combined: byBiometrics.sealed),
            let opened = try? ChaChaPoly.open(box, using: wrapping, authenticating: context(.biometrics))
        else { throw VaultError.wrongCode }
        return SymmetricKey(data: opened)
    }

    public static func addingBiometrics(
        to sealed: SealedVaultKey, key: SymmetricKey, hardware: any HardwareKeys
    ) async throws -> SealedVaultKey {
        _ = try await hardware.make(.biometrics, requiringBiometrics: true)
        let byBiometrics = try await wrap(
            key, with: .biometrics, code: nil, salt: sealed.salt, rounds: sealed.rounds, hardware: hardware)
        return SealedVaultKey(
            salt: sealed.salt, rounds: sealed.rounds, byCode: sealed.byCode, byBiometrics: byBiometrics)
    }

    public static func withoutBiometrics(
        _ sealed: SealedVaultKey, hardware: any HardwareKeys
    ) async throws -> SealedVaultKey {
        try? await hardware.remove(.biometrics)
        return SealedVaultKey(salt: sealed.salt, rounds: sealed.rounds, byCode: sealed.byCode, byBiometrics: nil)
    }

    private static func wrap(
        _ vaultKey: SymmetricKey, with id: HardwareKeyID, code: String?, salt: Data, rounds: Int,
        hardware: any HardwareKeys
    ) async throws -> SealedVaultKey.Wrapping {
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let wrapping = try await wrappingKey(
            id, code: code, salt: salt, rounds: rounds, ephemeral: ephemeral.publicKey.x963Representation,
            hardware: hardware, reason: "")
        let sealed = try ChaChaPoly.seal(
            vaultKey.withUnsafeBytes { Data($0) }, using: wrapping, authenticating: context(id))
        return SealedVaultKey.Wrapping(ephemeral: ephemeral.publicKey.x963Representation, sealed: sealed.combined)
    }

    private static func wrappingKey(
        _ id: HardwareKeyID, code: String?, salt: Data, rounds: Int, ephemeral: Data,
        hardware: any HardwareKeys, reason: String
    ) async throws -> SymmetricKey {
        let shared = try await hardware.agree(id, with: ephemeral, reason: reason)
        let fromCode = code.map { stretch($0, salt: salt, rounds: rounds) } ?? Data()
        return SymmetricKey(
            data: HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: shared + fromCode),
                salt: salt,
                info: context(id),
                outputByteCount: 32))
    }

    private static func context(_ id: HardwareKeyID) -> Data {
        CanonicalBytes.payload(domain: Domain.vaultKey, fields: [Data(id.rawValue.utf8)])
    }

    static func stretch(_ code: String, salt: Data, rounds: Int) -> Data {
        let password = Array(code.precomposedStringWithCanonicalMapping.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            password.withUnsafeBufferPointer { passwordBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                    passwordBytes.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds),
                    &derived, derived.count)
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 refused its own arguments")
        return Data(derived)
    }
}
