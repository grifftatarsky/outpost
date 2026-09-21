import Foundation

public protocol DocumentStore: Sendable {
    func load<Value: Decodable & Sendable>(_ type: Value.Type) async throws -> Value?
    func save(_ value: some Encodable & Sendable) async throws
    func clear() async throws
}

public actor FileDocumentStore: DocumentStore {
    private let url: URL
    private let backups: Backups
    private let fileManager: FileManager

    public init(url: URL, backups: Backups = .included, fileManager: FileManager = .default) {
        self.url = url
        self.backups = backups
        self.fileManager = fileManager
    }

    public func load<Value: Decodable & Sendable>(_ type: Value.Type) throws -> Value? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        backups.apply(to: url)
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    public func save(_ value: some Encodable & Sendable) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let scratch = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")

        try JSONEncoder().encode(value).write(to: scratch, options: .atomic)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: scratch.path)

        try CrossProcessLock(forDirectory: url.deletingLastPathComponent()).whileLocked {
            _ = try fileManager.replaceItemAt(url, withItemAt: scratch)
        }
        backups.apply(to: url)
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
