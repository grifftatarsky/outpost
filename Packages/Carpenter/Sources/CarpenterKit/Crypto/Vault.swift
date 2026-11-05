import CommonCrypto
import CryptoKit
import Foundation

public struct HardwareKeyID: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public enum Purpose: String, Sendable {
        case code = "vault.code"
        case biometrics = "vault.biometrics"
    }

    public static func fresh(_ purpose: Purpose) -> HardwareKeyID {
        HardwareKeyID(rawValue: "\(purpose.rawValue).\(UUID().uuidString)")
    }
}

public enum HardwareKeyError: Error, Hashable, Sendable {
    case unavailable
    case refused
    case noSuchKey
    case locked
}

public protocol HardwareKeys: Sendable {
    func make(_ id: HardwareKeyID, requiringBiometrics: Bool) async throws -> Data
    func publicKey(of id: HardwareKeyID) async throws -> Data?
    func agree(_ id: HardwareKeyID, with publicKey: Data, reason: String) async throws -> Data
    func remove(_ id: HardwareKeyID) async throws
}

public struct SealedVaultKey: Hashable, Sendable, Codable {
    public struct Wrapping: Hashable, Sendable, Codable {
        public let hardware: HardwareKeyID
        public let salt: Data
        public let ephemeral: Data
        public let sealed: Data

        public init(hardware: HardwareKeyID, salt: Data, ephemeral: Data, sealed: Data) {
            self.hardware = hardware
            self.salt = salt
            self.ephemeral = ephemeral
            self.sealed = sealed
        }
    }

    public let rounds: Int
    public let byCode: Wrapping
    public let byBiometrics: Wrapping?

    public init(rounds: Int, byCode: Wrapping, byBiometrics: Wrapping?) {
        self.rounds = rounds
        self.byCode = byCode
        self.byBiometrics = byBiometrics
    }

    public var usesBiometrics: Bool { byBiometrics != nil }

    public var hardwareKeys: Set<HardwareKeyID> { Set([byCode.hardware] + [byBiometrics?.hardware].compactMap { $0 }) }

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
        let byCode = try await wrap(vaultKey, for: .code, code: code, rounds: rounds, hardware: hardware)
        let byBiometrics =
            usingBiometrics
            ? try await wrap(vaultKey, for: .biometrics, code: nil, rounds: rounds, hardware: hardware) : nil
        return (vaultKey, SealedVaultKey(rounds: rounds, byCode: byCode, byBiometrics: byBiometrics))
    }

    public static func open(
        _ sealed: SealedVaultKey, with code: String, hardware: any HardwareKeys, reason: String
    ) async throws -> SymmetricKey {
        try await unwrap(sealed.byCode, code: code, rounds: sealed.rounds, hardware: hardware, reason: reason)
    }

    public static func openWithBiometrics(
        _ sealed: SealedVaultKey, hardware: any HardwareKeys, reason: String
    ) async throws -> SymmetricKey {
        guard let byBiometrics = sealed.byBiometrics else { throw VaultError.biometricsNotSet }
        return try await unwrap(byBiometrics, code: nil, rounds: sealed.rounds, hardware: hardware, reason: reason)
    }

    public static func changingCode(
        of sealed: SealedVaultKey, key: SymmetricKey, to code: String, hardware: any HardwareKeys
    ) async throws -> SealedVaultKey {
        let byCode = try await wrap(key, for: .code, code: code, rounds: sealed.rounds, hardware: hardware)
        return SealedVaultKey(rounds: sealed.rounds, byCode: byCode, byBiometrics: sealed.byBiometrics)
    }

    public static func addingBiometrics(
        to sealed: SealedVaultKey, key: SymmetricKey, hardware: any HardwareKeys
    ) async throws -> SealedVaultKey {
        let byBiometrics = try await wrap(key, for: .biometrics, code: nil, rounds: sealed.rounds, hardware: hardware)
        return SealedVaultKey(rounds: sealed.rounds, byCode: sealed.byCode, byBiometrics: byBiometrics)
    }

    public static func withoutBiometrics(_ sealed: SealedVaultKey) -> SealedVaultKey {
        SealedVaultKey(rounds: sealed.rounds, byCode: sealed.byCode, byBiometrics: nil)
    }

    public static func retire(_ replaced: SealedVaultKey, keeping kept: SealedVaultKey, hardware: any HardwareKeys)
        async throws
    {
        for id in replaced.hardwareKeys.subtracting(kept.hardwareKeys) { try await hardware.remove(id) }
    }

    private static func wrap(
        _ vaultKey: SymmetricKey, for purpose: HardwareKeyID.Purpose, code: String?, rounds: Int,
        hardware: any HardwareKeys
    ) async throws -> SealedVaultKey.Wrapping {
        let id = HardwareKeyID.fresh(purpose)
        _ = try await hardware.make(id, requiringBiometrics: purpose == .biometrics)
        let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let ephemeral = P256.KeyAgreement.PrivateKey().publicKey.x963Representation
        let wrapping = try await wrappingKey(
            id, purpose: purpose, code: code, salt: salt, rounds: rounds, ephemeral: ephemeral, hardware: hardware,
            reason: "")
        let sealed = try ChaChaPoly.seal(
            vaultKey.withUnsafeBytes { Data($0) }, using: wrapping, authenticating: context(purpose))
        return SealedVaultKey.Wrapping(hardware: id, salt: salt, ephemeral: ephemeral, sealed: sealed.combined)
    }

    private static func unwrap(
        _ wrapping: SealedVaultKey.Wrapping, code: String?, rounds: Int, hardware: any HardwareKeys, reason: String
    ) async throws -> SymmetricKey {
        let purpose: HardwareKeyID.Purpose = code == nil ? .biometrics : .code
        let key = try await wrappingKey(
            wrapping.hardware, purpose: purpose, code: code, salt: wrapping.salt, rounds: rounds,
            ephemeral: wrapping.ephemeral, hardware: hardware, reason: reason)
        guard let box = try? ChaChaPoly.SealedBox(combined: wrapping.sealed),
            let opened = try? ChaChaPoly.open(box, using: key, authenticating: context(purpose))
        else { throw VaultError.wrongCode }
        return SymmetricKey(data: opened)
    }

    private static func wrappingKey(
        _ id: HardwareKeyID, purpose: HardwareKeyID.Purpose, code: String?, salt: Data, rounds: Int,
        ephemeral: Data, hardware: any HardwareKeys, reason: String
    ) async throws -> SymmetricKey {
        let shared = try await hardware.agree(id, with: ephemeral, reason: reason)
        let fromCode = code.map { stretch($0, salt: salt, rounds: rounds) } ?? Data()
        return SymmetricKey(
            data: HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: shared + fromCode),
                salt: salt,
                info: context(purpose),
                outputByteCount: 32))
    }

    private static func context(_ purpose: HardwareKeyID.Purpose) -> Data {
        CanonicalBytes.payload(domain: Domain.vaultKey, fields: [Data(purpose.rawValue.utf8)])
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
