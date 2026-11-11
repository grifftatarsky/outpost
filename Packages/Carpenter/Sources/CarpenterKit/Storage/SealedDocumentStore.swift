import CryptoKit
import Foundation
import Synchronization

public final class OpenVault: Sendable {
    private struct Held {
        var key: SymmetricKey?
        var inUse = false
        var sealsWhatItWrites = true
    }

    private let held: Mutex<Held>

    public init(key: SymmetricKey? = nil) {
        held = Mutex(Held(key: key, inUse: key != nil))
    }

    public var isOpen: Bool { held.withLock { $0.key != nil } }

    public var isShut: Bool { held.withLock { $0.inUse && $0.key == nil } }

    public var isInUse: Bool { held.withLock { $0.inUse } }

    public func open(with key: SymmetricKey) {
        held.withLock { $0 = Held(key: key, inUse: true) }
    }

    public func shut() {
        held.withLock { $0.key = nil }
    }

    public func shutUntilOpened() {
        held.withLock { $0 = Held(key: nil, inUse: true) }
    }

    public func retire() {
        held.withLock { $0 = Held() }
    }

    public func writeInTheClear() throws {
        try held.withLock { held in
            guard held.key != nil else { throw VaultError.shut }
            held.sealsWhatItWrites = false
        }
    }

    public func sealingKey() throws -> SymmetricKey? {
        try held.withLock { held in
            if let key = held.key { return held.sealsWhatItWrites ? key : nil }
            if held.inUse { throw VaultError.shut }
            return nil
        }
    }

    public func openingKey() throws -> SymmetricKey {
        try held.withLock { held in
            guard let key = held.key else { throw VaultError.shut }
            return key
        }
    }
}

public struct SealedDocumentStore: DocumentStore {
    private let inner: any DocumentStore
    private let vault: OpenVault

    public init(around inner: any DocumentStore, vault: OpenVault) {
        self.inner = inner
        self.vault = vault
    }

    public func load<Value: Decodable & Sendable>(_ type: Value.Type) async throws -> Value? {
        guard let carried = (try? await inner.load(SealedDocument.self)) ?? nil else {
            return try await inner.load(type)
        }
        let box = try ChaChaPoly.SealedBox(combined: carried.sealed)
        let opened = try ChaChaPoly.open(box, using: try vault.openingKey(), authenticating: SealedDocument.context)
        return try JSONDecoder().decode(Value.self, from: opened)
    }

    public func save(_ value: some Encodable & Sendable) async throws {
        guard let key = try vault.sealingKey() else { return try await inner.save(value) }
        let sealed = try ChaChaPoly.seal(
            try JSONEncoder().encode(value), using: key, authenticating: SealedDocument.context)
        try await inner.save(SealedDocument(sealed: sealed.combined))
    }

    public func clear() async throws {
        try await inner.clear()
    }
}

public struct SealedDocument: Hashable, Sendable, Codable {
    public let sealed: Data

    public init(sealed: Data) {
        self.sealed = sealed
    }

    static let context = CanonicalBytes.payload(domain: Domain.vaultDocument, fields: [])
}

public struct SealedKeychainStore: KeychainStore {
    public static let keptInTheClear: Set<KeychainKey> = [ProtectionChoice.key, AppLockStore.key, SealedVaultKey.key]

    private static let mark = Data([0]) + Data("vault.sealed.1".utf8) + Data([0])

    private let inner: any KeychainStore
    private let vault: OpenVault

    public init(around inner: any KeychainStore, vault: OpenVault) {
        self.inner = inner
        self.vault = vault
    }

    public static func isSealed(_ stored: Data) -> Bool { stored.starts(with: mark) }

    public func data(for key: KeychainKey) async throws -> Data? {
        guard let stored = try await inner.data(for: key) else { return nil }
        guard Self.isSealed(stored) else { return stored }
        let box = try ChaChaPoly.SealedBox(combined: stored.dropFirst(Self.mark.count))
        return try ChaChaPoly.open(box, using: try vault.openingKey(), authenticating: Self.context(key))
    }

    public func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws {
        guard scope == .device, !Self.keptInTheClear.contains(key) else {
            return try await inner.set(data, for: key, scope: scope)
        }
        guard let sealing = try vault.sealingKey() else { return try await inner.set(data, for: key, scope: scope) }
        let sealed = try ChaChaPoly.seal(data, using: sealing, authenticating: Self.context(key))
        try await inner.set(Self.mark + sealed.combined, for: key, scope: scope)
    }

    public func remove(_ key: KeychainKey) async throws {
        try await inner.remove(key)
    }

    public func removeAll(_ scope: KeychainScope) async throws {
        try await inner.removeAll(scope)
    }

    public func protect(as protection: StorageProtection) async throws {
        try await inner.protect(as: protection)
    }

    private static func context(_ key: KeychainKey) -> Data {
        CanonicalBytes.payload(domain: Domain.vaultSecret, fields: [Data(key.rawValue.utf8)])
    }
}
