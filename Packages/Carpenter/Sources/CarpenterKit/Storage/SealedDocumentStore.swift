import CryptoKit
import Foundation

public actor OpenVault {
    private var key: SymmetricKey?

    public init(key: SymmetricKey? = nil) {
        self.key = key
    }

    public var isOpen: Bool { key != nil }

    public func open(with key: SymmetricKey) { self.key = key }

    public func shut() { key = nil }

    public func sealingKey() throws -> SymmetricKey {
        guard let key else { throw VaultError.shut }
        return key
    }
}

public actor SealedDocumentStore: DocumentStore {
    private let inner: any DocumentStore
    private let vault: OpenVault

    public init(around inner: any DocumentStore, vault: OpenVault) {
        self.inner = inner
        self.vault = vault
    }

    public func load<Value: Decodable & Sendable>(_ type: Value.Type) async throws -> Value? {
        let key = try await vault.sealingKey()
        guard let carried = try await inner.load(SealedDocument.self) else { return nil }
        let box = try ChaChaPoly.SealedBox(combined: carried.sealed)
        let opened = try ChaChaPoly.open(box, using: key, authenticating: SealedDocument.context)
        return try JSONDecoder().decode(Value.self, from: opened)
    }

    public func save(_ value: some Encodable & Sendable) async throws {
        let key = try await vault.sealingKey()
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
