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

    static let empty = LoadedLog(entries: [], discardedTrailingBytes: 0, termination: .complete)

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
    private let dial: ProtectionDial

    private let maximumRecordBytes: Int

    public static let defaultMaximumRecordBytes = 8 * 1024 * 1024

    public init(
        url: URL,
        maximumRecordBytes: Int = defaultMaximumRecordBytes,
        protection dial: ProtectionDial = ProtectionDial(),
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.maximumRecordBytes = maximumRecordBytes
        self.dial = dial
        self.fileManager = fileManager
    }

    public static func url(inDirectory directory: URL, named name: String = "log.carpenter") -> URL {
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
        }
    }

    public func loadAll() async throws -> LoadedLog {
        guard let data = try contents() else { return .empty }
        let framing = Framing(of: data, maximumRecordBytes: maximumRecordBytes)
        return framing.loaded(await framing.records.inParallel { lane in Self.decoded(lane, of: data) })
    }

    private func readAll() throws -> LoadedLog {
        guard let data = try contents() else { return .empty }
        let framing = Framing(of: data, maximumRecordBytes: maximumRecordBytes)
        return framing.loaded(Self.decoded(framing.records[...], of: data))
    }

    private func contents() throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private static func decoded(_ records: ArraySlice<Range<Int>>, of data: Data) -> [Entry?] {
        let decoder = JSONDecoder()
        return records.map { try? decoder.decode(Entry.self, from: data[$0]) }
    }

    private struct Framing {
        var records: [Range<Int>] = []
        var termination = LogTermination.complete
        let size: Int

        init(of data: Data, maximumRecordBytes: Int) {
            size = data.count
            var cursor = 0
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
                records.append(start..<(start + length))
                cursor = start + length
            }
        }

        func loaded(_ decoded: [Entry?]) -> LoadedLog {
            let readable = decoded.firstIndex { $0 == nil } ?? decoded.count
            let cut = readable < records.count
            let end = cut ? records[readable].lowerBound - 4 : records.last?.upperBound ?? 0
            var termination = cut ? .undecodableRecord : termination
            if termination == .complete, end < size { termination = .tornTail }
            return LoadedLog(
                entries: decoded[..<readable].compactMap(\.self),
                discardedTrailingBytes: size - end,
                termination: termination)
        }
    }

    public func compact() throws {
        let loaded = try readAll()
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
            let loaded = try readAll()
            let kept = loaded.entries.filter { !shouldRemove($0) }
            let removed = loaded.entries.count - kept.count
            guard removed > 0 else { return 0 }

            let directory = url.deletingLastPathComponent()
            let scratch = directory.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
            guard
                fileManager.createFile(
                    atPath: scratch.path,
                    contents: try Self.records(of: kept),
                    attributes: dial.current.fileAttributes)
            else { throw CocoaError(.fileWriteUnknown) }
            _ = try fileManager.replaceItemAt(url, withItemAt: scratch)
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
            attributes: dial.current.fileAttributes
        )
    }
}
