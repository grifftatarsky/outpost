import Foundation

public protocol MediaStore: Sendable {
    func store(_ sealed: Data, for id: AttachmentID) async throws
    func sealed(for id: AttachmentID) async throws -> Data?
    func remove(_ id: AttachmentID) async throws
    func removeAll() async throws
    func byteCount() async throws -> Int
}

public actor FileMediaStore: MediaStore {
    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public static func url(inDirectory directory: URL) -> URL {
        directory.appending(path: "media", directoryHint: .isDirectory)
    }

    private func url(for id: AttachmentID) -> URL {
        directory.appending(path: "\(id.rawValue.uuidString).sealed")
    }

    public func store(_ sealed: Data, for id: AttachmentID) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let scratch = directory.appending(path: ".\(id.rawValue.uuidString).\(UUID().uuidString)")
        try sealed.write(to: scratch, options: .atomic)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: scratch.path)
        _ = try fileManager.replaceItemAt(url(for: id), withItemAt: scratch)
    }

    public func sealed(for id: AttachmentID) throws -> Data? {
        let target = url(for: id)
        guard fileManager.fileExists(atPath: target.path) else { return nil }
        return try Data(contentsOf: target)
    }

    public func remove(_ id: AttachmentID) throws {
        let target = url(for: id)
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    public func removeAll() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    public func byteCount() throws -> Int {
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .reduce(0) { total, file in
                total + ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
    }
}

public actor MemoryMediaStore: MediaStore {
    private var files: [AttachmentID: Data] = [:]

    public init() {}

    public func store(_ sealed: Data, for id: AttachmentID) { files[id] = sealed }
    public func sealed(for id: AttachmentID) -> Data? { files[id] }
    public func remove(_ id: AttachmentID) { files[id] = nil }
    public func removeAll() { files = [:] }
    public func byteCount() -> Int { files.values.reduce(0) { $0 + $1.count } }
    public var count: Int { files.count }
}
