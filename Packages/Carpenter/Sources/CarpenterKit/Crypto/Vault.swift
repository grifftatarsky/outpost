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
        case recovery = "vault.recovery"
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
    public let byRecovery: Wrapping?

    public init(rounds: Int, byCode: Wrapping, byBiometrics: Wrapping?, byRecovery: Wrapping? = nil) {
        self.rounds = rounds
        self.byCode = byCode
        self.byBiometrics = byBiometrics
        self.byRecovery = byRecovery
    }

    public var usesBiometrics: Bool { byBiometrics != nil }

    public var hardwareKeys: Set<HardwareKeyID> {
        Set([byCode.hardware] + [byBiometrics?.hardware, byRecovery?.hardware].compactMap { $0 })
    }

    public static let key = KeychainKey("vault.key")
}

public enum VaultError: Error, Hashable, Sendable {
    case wrongCode
    case biometricsNotSet
    case recoveryNotSet
    case shut
}

public enum Vault {
    public static let rounds = 600_000

    private enum Opener {
        case code(String)
        case biometrics
        case recovery(Data)

        var purpose: HardwareKeyID.Purpose {
            switch self {
            case .code: .code
            case .biometrics: .biometrics
            case .recovery: .recovery
            }
        }

        func secret(salt: Data, rounds: Int) -> Data {
            switch self {
            case .code(let code): AppLock.derive(code, salt: salt, rounds: rounds)
            case .biometrics: Data()
            case .recovery(let secret): secret
            }
        }
    }

    public static func create(
        code: String, usingBiometrics: Bool, recovery: Data? = nil, hardware: any HardwareKeys,
        rounds: Int = Vault.rounds
    ) async throws -> (key: SymmetricKey, sealed: SealedVaultKey) {
        let vaultKey = SymmetricKey(size: .bits256)
        let byCode = try await wrap(vaultKey, for: .code(code), rounds: rounds, hardware: hardware)
        let byBiometrics =
            usingBiometrics ? try await wrap(vaultKey, for: .biometrics, rounds: rounds, hardware: hardware) : nil
        var byRecovery: SealedVaultKey.Wrapping?
        if let recovery { byRecovery = try await wrap(vaultKey, for: .recovery(recovery), rounds: rounds, hardware: hardware) }
        return (
            vaultKey, SealedVaultKey(rounds: rounds, byCode: byCode, byBiometrics: byBiometrics, byRecovery: byRecovery)
        )
    }

    public static func open(
        _ sealed: SealedVaultKey, with code: String, hardware: any HardwareKeys, reason: String
    ) async throws -> SymmetricKey {
        try await unwrap(sealed.byCode, with: .code(code), rounds: sealed.rounds, hardware: hardware, reason: reason)
    }

    public static func openWithBiometrics(
        _ sealed: SealedVaultKey, hardware: any HardwareKeys, reason: String
    ) async throws -> SymmetricKey {
        guard let byBiometrics = sealed.byBiometrics else { throw VaultError.biometricsNotSet }
        return try await unwrap(byBiometrics, with: .biometrics, rounds: sealed.rounds, hardware: hardware, reason: reason)
    }

    public static func openWithRecovery(
        _ sealed: SealedVaultKey, secret: Data, hardware: any HardwareKeys
    ) async throws -> SymmetricKey {
        guard let byRecovery = sealed.byRecovery else { throw VaultError.recoveryNotSet }
        return try await unwrap(byRecovery, with: .recovery(secret), rounds: sealed.rounds, hardware: hardware, reason: "")
    }

    public static func changingCode(
        of sealed: SealedVaultKey, key: SymmetricKey, to code: String, hardware: any HardwareKeys
    ) async throws -> SealedVaultKey {
        let byCode = try await wrap(key, for: .code(code), rounds: sealed.rounds, hardware: hardware)
        return SealedVaultKey(
            rounds: sealed.rounds, byCode: byCode, byBiometrics: sealed.byBiometrics, byRecovery: sealed.byRecovery)
    }

    public static func addingBiometrics(
        to sealed: SealedVaultKey, key: SymmetricKey, hardware: any HardwareKeys
    ) async throws -> SealedVaultKey {
        let byBiometrics = try await wrap(key, for: .biometrics, rounds: sealed.rounds, hardware: hardware)
        return SealedVaultKey(
            rounds: sealed.rounds, byCode: sealed.byCode, byBiometrics: byBiometrics, byRecovery: sealed.byRecovery)
    }

    public static func withoutBiometrics(_ sealed: SealedVaultKey) -> SealedVaultKey {
        SealedVaultKey(rounds: sealed.rounds, byCode: sealed.byCode, byBiometrics: nil, byRecovery: sealed.byRecovery)
    }

    public static func retire(_ replaced: SealedVaultKey, keeping kept: SealedVaultKey, hardware: any HardwareKeys)
        async throws
    {
        for id in replaced.hardwareKeys.subtracting(kept.hardwareKeys) { try await hardware.remove(id) }
    }

    private static func wrap(
        _ vaultKey: SymmetricKey, for opener: Opener, rounds: Int, hardware: any HardwareKeys
    ) async throws -> SealedVaultKey.Wrapping {
        let id = HardwareKeyID.fresh(opener.purpose)
        _ = try await hardware.make(id, requiringBiometrics: opener.purpose == .biometrics)
        let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let ephemeral = P256.KeyAgreement.PrivateKey().publicKey.x963Representation
        let wrapping = try await wrappingKey(
            id, opener: opener, salt: salt, rounds: rounds, ephemeral: ephemeral, hardware: hardware, reason: "")
        let sealed = try ChaChaPoly.seal(
            vaultKey.withUnsafeBytes { Data($0) }, using: wrapping, authenticating: context(opener.purpose))
        return SealedVaultKey.Wrapping(hardware: id, salt: salt, ephemeral: ephemeral, sealed: sealed.combined)
    }

    private static func unwrap(
        _ wrapping: SealedVaultKey.Wrapping, with opener: Opener, rounds: Int, hardware: any HardwareKeys,
        reason: String
    ) async throws -> SymmetricKey {
        let key = try await wrappingKey(
            wrapping.hardware, opener: opener, salt: wrapping.salt, rounds: rounds, ephemeral: wrapping.ephemeral,
            hardware: hardware, reason: reason)
        guard let box = try? ChaChaPoly.SealedBox(combined: wrapping.sealed),
            let opened = try? ChaChaPoly.open(box, using: key, authenticating: context(opener.purpose))
        else { throw VaultError.wrongCode }
        return SymmetricKey(data: opened)
    }

    private static func wrappingKey(
        _ id: HardwareKeyID, opener: Opener, salt: Data, rounds: Int, ephemeral: Data, hardware: any HardwareKeys,
        reason: String
    ) async throws -> SymmetricKey {
        let shared = try await hardware.agree(id, with: ephemeral, reason: reason)
        return SymmetricKey(
            data: HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: shared + opener.secret(salt: salt, rounds: rounds)),
                salt: salt,
                info: context(opener.purpose),
                outputByteCount: 32))
    }

    private static func context(_ purpose: HardwareKeyID.Purpose) -> Data {
        CanonicalBytes.payload(domain: Domain.vaultKey, fields: [Data(purpose.rawValue.utf8)])
    }
}

public actor VaultKeeper {
    private let keychain: any KeychainStore
    private let hardware: any HardwareKeys
    private let rounds: Int
    public nonisolated let vault: OpenVault
    public nonisolated let checksBiometricsItself: Bool

    public init(
        keychain: any KeychainStore, hardware: any HardwareKeys, vault: OpenVault, rounds: Int = Vault.rounds,
        checksBiometricsItself: Bool = true
    ) {
        self.keychain = keychain
        self.hardware = hardware
        self.vault = vault
        self.rounds = rounds
        self.checksBiometricsItself = checksBiometricsItself
    }

    public func sealed() async throws -> SealedVaultKey? {
        try await keychain.data(for: SealedVaultKey.key).map { try JSONDecoder().decode(SealedVaultKey.self, from: $0) }
    }

    @discardableResult
    public func shutIfThereIsOne() async throws -> Bool {
        guard try await sealed() != nil else { return false }
        if !vault.isOpen { vault.shutUntilOpened() }
        return true
    }

    public func make(code: String, usingBiometrics: Bool, recovery: Data?) async throws -> SymmetricKey {
        let replaced = try await sealed()
        let made = try await Vault.create(
            code: code, usingBiometrics: usingBiometrics, recovery: recovery, hardware: hardware, rounds: rounds)
        try await keep(made.sealed, replacing: replaced)
        return made.key
    }

    public func create(code: String, usingBiometrics: Bool, recovery: Data?) async throws {
        vault.open(with: try await make(code: code, usingBiometrics: usingBiometrics, recovery: recovery))
    }

    public func open(with code: String, reason: String = "") async throws -> Bool {
        try await opening { try await Vault.open($0, with: code, hardware: hardware, reason: reason) }
    }

    public func openWithBiometrics(reason: String) async throws -> Bool {
        try await opening { try await Vault.openWithBiometrics($0, hardware: hardware, reason: reason) }
    }

    public func openWithRecovery(_ secret: Data) async throws -> Bool {
        try await opening { try await Vault.openWithRecovery($0, secret: secret, hardware: hardware) }
    }

    public nonisolated func shut() {
        vault.shut()
    }

    public func changeCode(to code: String) async throws {
        guard let current = try await sealed(), let key = try vault.sealingKey() else { throw VaultError.shut }
        try await keep(try await Vault.changingCode(of: current, key: key, to: code, hardware: hardware), replacing: current)
    }

    public func setBiometrics(_ on: Bool) async throws {
        guard let current = try await sealed(), let key = try vault.sealingKey() else { throw VaultError.shut }
        guard on != current.usesBiometrics else { return }
        let changed =
            on ? try await Vault.addingBiometrics(to: current, key: key, hardware: hardware) : Vault.withoutBiometrics(current)
        try await keep(changed, replacing: current)
    }

    public func destroy() async throws {
        guard let current = try await sealed() else { return vault.retire() }
        try await keychain.remove(SealedVaultKey.key)
        for id in current.hardwareKeys { try? await hardware.remove(id) }
        vault.retire()
    }

    private func opening(_ unwrap: (SealedVaultKey) async throws -> SymmetricKey) async throws -> Bool {
        guard let current = try await sealed() else { throw VaultError.shut }
        do {
            vault.open(with: try await unwrap(current))
            return true
        } catch VaultError.wrongCode {
            return false
        } catch HardwareKeyError.refused {
            return false
        }
    }

    private func keep(_ new: SealedVaultKey, replacing old: SealedVaultKey?) async throws {
        try await keychain.set(try JSONEncoder().encode(new), for: SealedVaultKey.key, scope: .device)
        if let old { try await Vault.retire(old, keeping: new, hardware: hardware) }
    }
}
