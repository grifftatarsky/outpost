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

    public let discardedBytes: Int

    public let termination: LogTermination

    public var isDamaged: Bool { discardedBytes > 0 }

    static let empty = LoadedLog(entries: [], discardedBytes: 0, termination: .complete)

    public init(entries: [Entry], discardedBytes: Int, termination: LogTermination) {
        self.entries = entries
        self.discardedBytes = discardedBytes
        self.termination = termination
    }
}

public enum StorageError: Error, Hashable, Sendable {
    case unreadable
    case notADirectory
    case recordTooLarge
}

public actor FileLogStore: LogStore {
    private let url: URL
    private let fileManager: FileManager
    private let dial: ProtectionDial
    private let flushToDrive: @Sendable (FileHandle) throws -> Void

    private let maximumRecordBytes: Int

    private var wholeThrough: UInt64?

    public static let defaultMaximumRecordBytes = 8 * 1024 * 1024

    public init(
        url: URL,
        maximumRecordBytes: Int = defaultMaximumRecordBytes,
        protection dial: ProtectionDial = ProtectionDial(),
        fileManager: FileManager = .default
    ) {
        self.init(
            url: url, maximumRecordBytes: maximumRecordBytes, protection: dial, fileManager: fileManager,
            flushing: Self.flushAllTheWayToTheDrive)
    }

    init(
        url: URL,
        maximumRecordBytes: Int = defaultMaximumRecordBytes,
        protection dial: ProtectionDial = ProtectionDial(),
        fileManager: FileManager = .default,
        flushing: @escaping @Sendable (FileHandle) throws -> Void
    ) {
        self.url = url
        self.maximumRecordBytes = maximumRecordBytes
        self.dial = dial
        self.fileManager = fileManager
        flushToDrive = flushing
    }

    public static func url(inDirectory directory: URL, named name: String = "log.carpenter") -> URL {
        directory.appending(path: name)
    }

    private static func flushAllTheWayToTheDrive(_ handle: FileHandle) throws {
        guard fcntl(handle.fileDescriptor, F_FULLFSYNC) == -1 else { return }
        try handle.synchronize()
    }

    private var lock: CrossProcessLock { CrossProcessLock(forDirectory: url.deletingLastPathComponent()) }

    private var scratch: URL {
        url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).rewrite")
    }

    private func records(of entries: [Entry]) throws -> Data {
        let encoder = JSONEncoder()
        var buffer = Data()
        for entry in entries {
            let record = try encoder.encode(entry)
            guard record.count <= maximumRecordBytes else { throw StorageError.recordTooLarge }
            buffer.append(withUnsafeBytes(of: UInt32(record.count).bigEndian) { Data($0) })
            buffer.append(record)
        }
        return buffer
    }

    public func append(_ entries: [Entry]) throws {
        guard !entries.isEmpty else { return }

        let buffer = try records(of: entries)

        try lock.whileLocked {
            try ensureFileExists()
            try repairIfBroken()

            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            let end = try handle.seekToEnd()
            do {
                try handle.write(contentsOf: buffer)
                try flushToDrive(handle)
            } catch {
                try? handle.truncate(atOffset: end)
                throw error
            }
            wholeThrough = end + UInt64(buffer.count)
        }
    }

    private func repairIfBroken() throws {
        let size = try fileManager.attributesOfItem(atPath: url.path)[.size] as? UInt64
        guard size != wholeThrough, let data = try contents() else { return }

        if Framing(of: data, maximumRecordBytes: maximumRecordBytes).isWhole(data) {
            wholeThrough = size
        } else {
            try rewrite(keeping: try readAll().entries)
        }
    }

    public func loadAll() async throws -> LoadedLog {
        guard let data = try contents() else { return .empty }
        let framing = Framing(of: data, maximumRecordBytes: maximumRecordBytes)
        return framing.loaded(await framing.records.inParallel { lane in Self.decoded(lane, of: data) }, from: data)
    }

    private func readAll() throws -> LoadedLog {
        guard let data = try contents() else { return .empty }
        let framing = Framing(of: data, maximumRecordBytes: maximumRecordBytes)
        return framing.loaded(Self.decoded(framing.records[...], of: data), from: data)
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
        private static let openingBrace = Data("{".utf8)

        var records: [Range<Int>] = []
        private var end = 0
        private let maximumRecordBytes: Int

        init(of data: Data, maximumRecordBytes: Int) {
            self.maximumRecordBytes = maximumRecordBytes
            while let record = record(at: end, in: data) {
                records.append(record)
                end = record.upperBound
            }
        }

        func isWhole(_ data: Data) -> Bool { end == data.count }

        private func length(at offset: Int, in data: Data) -> Int? {
            guard offset + 4 <= data.count else { return nil }
            return Int(
                data[offset..<(offset + 4)].withUnsafeBytes {
                    UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))
                })
        }

        private func record(at offset: Int, in data: Data) -> Range<Int>? {
            guard let length = length(at: offset, in: data), length > 0, length <= maximumRecordBytes,
                offset + 4 + length <= data.count
            else { return nil }
            return (offset + 4)..<(offset + 4 + length)
        }

        func loaded(_ decoded: [Entry?], from data: Data) -> LoadedLog {
            let readable = decoded.firstIndex { $0 == nil } ?? decoded.count
            let damage = readable < records.count ? records[readable].lowerBound - 4 : end
            let entries = decoded[..<readable].compactMap(\.self)
            guard damage < data.count else {
                return LoadedLog(entries: entries, discardedBytes: 0, termination: .complete)
            }
            let found = recordsPast(damage, in: data)
            return LoadedLog(
                entries: entries + found.entries,
                discardedBytes: data.count - damage - found.bytes,
                termination: termination(at: damage, in: data))
        }

        private func recordsPast(_ damage: Int, in data: Data) -> (entries: [Entry], bytes: Int) {
            let decoder = JSONDecoder()
            var entries: [Entry] = []
            var bytes = 0
            var search = damage + 5
            while search < data.count,
                let brace = data.range(of: Self.openingBrace, in: search..<data.count)?.lowerBound
            {
                search = brace + 1
                guard let record = record(at: brace - 4, in: data),
                    let entry = try? decoder.decode(Entry.self, from: data[record])
                else { continue }
                entries.append(entry)
                bytes += record.count + 4
                search = record.upperBound + 4
            }
            return (entries, bytes)
        }

        private func termination(at offset: Int, in data: Data) -> LogTermination {
            guard let length = length(at: offset, in: data) else { return .tornTail }
            if length > maximumRecordBytes { return .recordTooLarge }
            return length == 0 || offset + 4 + length > data.count ? .tornTail : .undecodableRecord
        }
    }

    public func compact() throws {
        try lock.whileLocked {
            let loaded = try readAll()
            guard loaded.isDamaged else { return }
            try rewrite(keeping: loaded.entries)
        }
    }

    private func rewrite(keeping entries: [Entry]) throws {
        let contents = try records(of: entries)
        guard fileManager.createFile(atPath: scratch.path, contents: nil, attributes: dial.current.fileAttributes)
        else { throw CocoaError(.fileWriteUnknown) }

        let handle = try FileHandle(forWritingTo: scratch)
        defer { try? handle.close() }
        try handle.write(contentsOf: contents)
        try flushToDrive(handle)

        _ = try fileManager.replaceItemAt(url, withItemAt: scratch)
        wholeThrough = UInt64(contents.count)
    }

    public func removeAll() throws {
        for file in [url, scratch] where fileManager.fileExists(atPath: file.path) {
            try fileManager.removeItem(at: file)
        }
    }

    @discardableResult
    public func removeEntries(where shouldRemove: @escaping @Sendable (Entry) -> Bool) throws -> Int {
        try lock.whileLocked {
            let loaded = try readAll()
            let kept = loaded.entries.filter { !shouldRemove($0) }
            let removed = loaded.entries.count - kept.count
            guard removed > 0 else { return 0 }

            try rewrite(keeping: kept)
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
