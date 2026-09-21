import Foundation

public protocol LogStore: Sendable {
    func append(_ entries: [Entry]) async throws
    func loadAll() async throws -> LoadedLog
    func removeAll() async throws
    @discardableResult
    func removeEntries(where shouldRemove: @escaping @Sendable (Entry) -> Bool) async throws -> Int
}

public enum LogTermination: Hashable, Sendable {
    case complete
    case tornTail
    case recordTooLarge
    case undecodableRecord
}

public struct LoadedLog: Sendable {
    public let entries: [Entry]

    public let discardedTrailingBytes: Int

    public let termination: LogTermination

    public var wasTruncated: Bool { discardedTrailingBytes > 0 }

    public init(entries: [Entry], discardedTrailingBytes: Int, termination: LogTermination) {
        self.entries = entries
        self.discardedTrailingBytes = discardedTrailingBytes
        self.termination = termination
    }
}

public enum StorageError: Error, Hashable, Sendable {
    case unreadable
    case notADirectory
}

public actor FileLogStore: LogStore {
    private let url: URL
    private let fileManager: FileManager

    private let maximumRecordBytes: Int
    private let backups: Backups

    public static let defaultMaximumRecordBytes = 8 * 1024 * 1024

    public init(
        url: URL,
        maximumRecordBytes: Int = defaultMaximumRecordBytes,
        backups: Backups = .included,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.maximumRecordBytes = maximumRecordBytes
        self.backups = backups
        self.fileManager = fileManager
    }

    public static func url(
        inDirectory directory: URL, named name: String = StorageLocation.logName
    ) -> URL {
        directory.appending(path: name)
    }

    private static func records(of entries: [Entry]) throws -> Data {
        let encoder = JSONEncoder()
        var buffer = Data()
        for entry in entries {
            let record = try encoder.encode(entry)
            buffer.append(withUnsafeBytes(of: UInt32(record.count).bigEndian) { Data($0) })
            buffer.append(record)
        }
        return buffer
    }

    public func append(_ entries: [Entry]) throws {
        guard !entries.isEmpty else { return }

        let buffer = try Self.records(of: entries)

        try CrossProcessLock(forDirectory: url.deletingLastPathComponent()).whileLocked {
            try ensureFileExists()

            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: buffer)
            backups.apply(to: url)
        }
    }

    public func loadAll() throws -> LoadedLog {
        guard fileManager.fileExists(atPath: url.path) else {
            return LoadedLog(entries: [], discardedTrailingBytes: 0, termination: .complete)
        }
        backups.apply(to: url)

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()

        var entries: [Entry] = []
        var cursor = 0
        var termination = LogTermination.complete

        while cursor + 4 <= data.count {
            let length = Int(
                data[cursor..<(cursor + 4)].withUnsafeBytes {
                    UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))
                })

            let start = cursor + 4
            guard length > 0, length <= maximumRecordBytes else {
                termination = .recordTooLarge
                break
            }
            guard start + length <= data.count else {
                termination = .tornTail
                break
            }

            guard let entry = try? decoder.decode(Entry.self, from: data[start..<(start + length)])
            else {
                termination = .undecodableRecord
                break
            }

            entries.append(entry)
            cursor = start + length
        }

        if termination == .complete, cursor < data.count { termination = .tornTail }

        return LoadedLog(
            entries: entries,
            discardedTrailingBytes: data.count - cursor,
            termination: termination)
    }

    public func compact() throws {
        let loaded = try loadAll()
        guard loaded.wasTruncated else { return }

        try fileManager.removeItem(at: url)
        try append(loaded.entries)
    }

    public func removeAll() throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    @discardableResult
    public func removeEntries(where shouldRemove: @escaping @Sendable (Entry) -> Bool) throws -> Int {
        try CrossProcessLock(forDirectory: url.deletingLastPathComponent()).whileLocked {
            let loaded = try loadAll()
            let kept = loaded.entries.filter { !shouldRemove($0) }
            let removed = loaded.entries.count - kept.count
            guard removed > 0 else { return 0 }

            let directory = url.deletingLastPathComponent()
            let scratch = directory.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
            guard
                fileManager.createFile(
                    atPath: scratch.path,
                    contents: try Self.records(of: kept),
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            else { throw CocoaError(.fileWriteUnknown) }
            _ = try fileManager.replaceItemAt(url, withItemAt: scratch)
            backups.apply(to: url)
            return removed
        }
    }

    private func ensureFileExists() throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        fileManager.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }
}
