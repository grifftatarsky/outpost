import Foundation

public struct ReadOnlyLogStore: LogStore {
    private let base: any LogStore

    public init(_ base: any LogStore) {
        self.base = base
    }

    public func append(_ entries: [Entry]) async throws {}

    public func loadAll() async throws -> LoadedLog { try await base.loadAll() }

    public func removeAll() async throws {}

    @discardableResult
    public func removeEntries(where shouldRemove: @escaping @Sendable (Entry) -> Bool) async throws -> Int {
        0
    }
}

public struct ReadOnlyDocumentStore: DocumentStore {
    private let base: any DocumentStore

    public init(_ base: any DocumentStore) {
        self.base = base
    }

    public func load<Value: Decodable & Sendable>(_ type: Value.Type) async throws -> Value? {
        try await base.load(type)
    }

    public func save(_ value: some Encodable & Sendable) async throws {}

    public func clear() async throws {}
}

public struct ReadOnlyKeychainStore: KeychainStore {
    private let base: any KeychainStore

    public init(_ base: any KeychainStore) {
        self.base = base
    }

    public func data(for key: KeychainKey) async throws -> Data? { try await base.data(for: key) }

    public func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws {}

    public func remove(_ key: KeychainKey) async throws {}

    public func removeAll() async throws {}
}
