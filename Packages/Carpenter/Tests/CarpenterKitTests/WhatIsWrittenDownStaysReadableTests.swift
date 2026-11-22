import Foundation
import Testing

@testable import CarpenterKit

private final class StopsBeforeTheSwap: FileManager {
    override func replaceItem(
        at originalItemURL: URL, withItemAt newItemURL: URL, backupItemName: String?,
        options: FileManager.ItemReplacementOptions = [],
        resultingItemURL resultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
    ) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

private final class FlushLog: @unchecked Sendable {
    private let lock = NSLock()
    private var flushed = 0
    private var refuses = false

    var flushes: Int { lock.withLock { flushed } }
    func refuse(_ value: Bool) { lock.withLock { refuses = value } }

    func flush(_ handle: FileHandle) throws {
        try lock.withLock {
            if refuses { throw Refused() }
            flushed += 1
        }
        try handle.synchronize()
    }
}

private struct Refused: Error {}

@Suite("What is written down stays readable", .serialized, .tags(.storage))
struct WhatIsWrittenDownStaysReadableTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func scratch() -> URL {
        TestScratch.root
            .appending(path: "carpenter-tests-\(UUID().uuidString)")
            .appending(path: "log.carpenter")
    }

    private func posts(_ count: Int, by author: inout Author) throws -> [Entry] {
        try (0..<count).map { try author.post("entry \($0)", at: start.addingTimeInterval(Double($0))) }
    }

    private func frame(_ body: Data) -> Data {
        withUnsafeBytes(of: UInt32(body.count).bigEndian) { Data($0) } + body
    }

    private func cut(_ bytes: Int, from url: URL) throws {
        let whole = try Data(contentsOf: url)
        try whole.prefix(whole.count - bytes).write(to: url)
    }

    @Test("A record written after a torn tail is read back")
    func appendAfterATornTailIsStillReadBack() async throws {
        let url = scratch()
        var alice = Author()
        let written = try posts(3, by: &alice)
        let store = FileLogStore(url: url)
        try await store.append(Array(written.prefix(2)))
        try cut(40, from: url)

        try await store.append([written[2]])

        let loaded = try await FileLogStore(url: url).loadAll()
        #expect(loaded.entries == [written[0], written[2]])
        #expect(loaded.termination == .complete)
        #expect(loaded.discardedBytes == 0)
    }

    @Test("A torn tail left by a process that died is repaired by the next one to write")
    func aNewProcessRepairsTheTail() async throws {
        let url = scratch()
        var alice = Author()
        let written = try posts(3, by: &alice)
        try await FileLogStore(url: url).append(Array(written.prefix(2)))
        try cut(40, from: url)

        try await FileLogStore(url: url).append([written[2]])

        let loaded = try await FileLogStore(url: url).loadAll()
        #expect(loaded.entries == [written[0], written[2]])
        #expect(loaded.termination == .complete)
    }

    @Test("A tail cut inside a length header is repaired too")
    func aTailCutInsideAHeader() async throws {
        let url = scratch()
        var alice = Author()
        let written = try posts(3, by: &alice)
        let store = FileLogStore(url: url)
        try await store.append(Array(written.prefix(2)))
        var data = try Data(contentsOf: url)
        data.append(contentsOf: [0, 0, 1])
        try data.write(to: url)

        try await store.append([written[2]])

        let loaded = try await FileLogStore(url: url).loadAll()
        #expect(loaded.entries == written)
        #expect(loaded.termination == .complete)
    }

    @Test("A tail of zeros reads as a torn tail and the next write clears it")
    func aZeroFilledTail() async throws {
        let url = scratch()
        var alice = Author()
        let written = try posts(3, by: &alice)
        let store = FileLogStore(url: url)
        try await store.append(Array(written.prefix(2)))
        var data = try Data(contentsOf: url)
        data.append(Data(repeating: 0, count: 4_096))
        try data.write(to: url)

        let torn = try await store.loadAll()
        #expect(torn.entries == Array(written.prefix(2)))
        #expect(torn.termination == .tornTail)
        #expect(torn.discardedBytes == 4_096)

        try await store.append([written[2]])

        let loaded = try await FileLogStore(url: url).loadAll()
        #expect(loaded.entries == written)
        #expect(loaded.termination == .complete)
    }

    @Test("Records an older build appended after a torn tail are found and kept")
    func recordsAppendedAfterTheTearAreFound() async throws {
        let url = scratch()
        var alice = Author()
        let written = try posts(5, by: &alice)
        let store = FileLogStore(url: url)
        try await store.append(Array(written.prefix(2)))
        try cut(40, from: url)
        var data = try Data(contentsOf: url)
        for entry in written[2..<4] { data.append(frame(try JSONEncoder().encode(entry))) }
        try data.write(to: url)

        let damaged = try await FileLogStore(url: url).loadAll()
        #expect(damaged.entries == [written[0], written[2], written[3]])
        #expect(damaged.termination == .undecodableRecord)
        #expect(damaged.discardedBytes > 0)

        try await FileLogStore(url: url).append([written[4]])

        let repaired = try await FileLogStore(url: url).loadAll()
        #expect(repaired.entries == [written[0], written[2], written[3], written[4]])
        #expect(repaired.termination == .complete)
    }

    @Test("A garbled record costs that record and nothing after it")
    func aGarbledRecordCostsOnlyItself() async throws {
        let url = scratch()
        var alice = Author()
        let written = try posts(5, by: &alice)
        let store = FileLogStore(url: url)
        try await store.append(Array(written.prefix(2)))
        var data = try Data(contentsOf: url)
        let garbled = frame(Data(repeating: 0x41, count: 500))
        data.append(garbled)
        for entry in written[2...] { data.append(frame(try JSONEncoder().encode(entry))) }
        try data.write(to: url)

        let loaded = try await store.loadAll()

        #expect(loaded.entries == written)
        #expect(loaded.termination == .undecodableRecord)
        #expect(loaded.discardedBytes == garbled.count)
    }

    @Test("A record past the ceiling in the middle of a log is stepped over and the rest still reads")
    func anOverCeilingRecordIsSteppedOver() async throws {
        let url = scratch()
        var alice = Author()
        let written = try posts(4, by: &alice)
        let store = FileLogStore(url: url, maximumRecordBytes: 1_024)
        try await store.append(Array(written.prefix(2)))
        var data = try Data(contentsOf: url)
        let poison = frame(Data("{\"payload\":\"".utf8) + Data(repeating: 0x41, count: 4_096) + Data("\"}".utf8))
        data.append(poison)
        data.append(frame(try JSONEncoder().encode(written[2])))
        try data.write(to: url)

        let loaded = try await FileLogStore(url: url, maximumRecordBytes: 1_024).loadAll()

        #expect(loaded.entries == Array(written.prefix(3)))
        #expect(loaded.termination == .recordTooLarge)
        #expect(loaded.discardedBytes == poison.count)

        try await FileLogStore(url: url, maximumRecordBytes: 1_024).append([written[3]])

        let repaired = try await FileLogStore(url: url, maximumRecordBytes: 1_024).loadAll()
        #expect(repaired.entries == written)
        #expect(repaired.termination == .complete)
    }

    @Test("A room deleted over a damaged log keeps everything past the damage")
    func removingEntriesKeepsWhatIsPastTheDamage() async throws {
        let url = scratch()
        var alice = Author()
        let written = try posts(4, by: &alice)
        let store = FileLogStore(url: url, maximumRecordBytes: 1_024)
        try await store.append([written[0]])
        var data = try Data(contentsOf: url)
        data.append(frame(Data(repeating: 0x41, count: 4_096)))
        for entry in written[1...] { data.append(frame(try JSONEncoder().encode(entry))) }
        try data.write(to: url)

        let removed = try await store.removeEntries { $0.hash == written[3].hash }

        #expect(removed == 1)
        let loaded = try await store.loadAll()
        #expect(loaded.entries == Array(written.prefix(3)))
        #expect(loaded.termination == .complete)
    }

    @Test("A record past the ceiling is refused at write and nothing is written")
    func anOverCeilingRecordIsRefusedAtWrite() async throws {
        let url = scratch()
        var alice = Author()
        let kept = try alice.post("kept", at: start)
        let store = FileLogStore(url: url, maximumRecordBytes: 1_024)
        try await store.append([kept])
        let before = try Data(contentsOf: url)

        let small = try alice.post("small", at: start)
        let large = try alice.post(String(repeating: "x", count: 4_096), at: start)

        await #expect(throws: StorageError.recordTooLarge) { try await store.append([small, large]) }

        #expect(try Data(contentsOf: url) == before, "a refused batch left part of itself on disk")
    }

    @Test("A compaction stopped before the swap leaves the old file whole")
    func aCompactionThatDiesLeavesTheOldFile() async throws {
        let url = scratch()
        var alice = Author()
        let store = FileLogStore(url: url, fileManager: StopsBeforeTheSwap())
        let written = try posts(3, by: &alice)
        try await store.append(written)
        try cut(40, from: url)
        let before = try Data(contentsOf: url)

        await #expect(throws: (any Error).self) { try await store.compact() }

        #expect(try Data(contentsOf: url) == before, "the log was touched before its replacement was in place")
        #expect(try await FileLogStore(url: url).loadAll().entries == Array(written.prefix(2)))
    }

    @Test("A repair stopped before the swap fails the write and leaves the old file whole")
    func aRepairThatDiesLeavesTheOldFile() async throws {
        let url = scratch()
        var alice = Author()
        let store = FileLogStore(url: url, fileManager: StopsBeforeTheSwap())
        let written = try posts(3, by: &alice)
        try await store.append(Array(written.prefix(2)))
        try cut(40, from: url)
        let before = try Data(contentsOf: url)

        await #expect(throws: (any Error).self) { try await store.append([written[2]]) }

        #expect(try Data(contentsOf: url) == before)
    }

    @Test("Compacting leaves no second copy of the log beside it")
    func compactingLeavesNothingBehind() async throws {
        let url = scratch()
        var alice = Author()
        let store = FileLogStore(url: url)
        try await store.append(try posts(3, by: &alice))
        try cut(40, from: url)

        try await store.compact()

        let beside = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(beside.filter { $0 != ".carpenter.lock" } == ["log.carpenter"])
    }

    @Test("Erasing the log takes a replacement a dead process left behind with it")
    func erasingTakesTheScratchFile() async throws {
        let url = scratch()
        var alice = Author()
        let store = FileLogStore(url: url, fileManager: StopsBeforeTheSwap())
        try await store.append(try posts(3, by: &alice))
        try cut(40, from: url)
        await #expect(throws: (any Error).self) { try await store.compact() }

        try await store.removeAll()

        let beside = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(beside.filter { $0 != ".carpenter.lock" } == [])
    }

    @Test("An append returns only after the bytes were flushed to the drive")
    func anAppendWaitsForTheDrive() async throws {
        let url = scratch()
        var alice = Author()
        let drive = FlushLog()
        let store = FileLogStore(url: url, flushing: { try drive.flush($0) })

        try await store.append(try posts(1, by: &alice))

        #expect(drive.flushes == 1)
    }

    @Test("A replacement is flushed to the drive before it takes the log's place")
    func aReplacementIsFlushedBeforeTheSwap() async throws {
        let url = scratch()
        var alice = Author()
        try await FileLogStore(url: url).append(try posts(3, by: &alice))
        try cut(40, from: url)
        let drive = FlushLog()
        let store = FileLogStore(url: url, fileManager: StopsBeforeTheSwap(), flushing: { try drive.flush($0) })

        await #expect(throws: (any Error).self) { try await store.compact() }

        #expect(drive.flushes == 1, "the log was swapped for a file that had not reached the drive")
    }

    @Test("A write the drive would not confirm leaves nothing behind")
    func aFailedFlushTakesTheBytesBack() async throws {
        let url = scratch()
        var alice = Author()
        let drive = FlushLog()
        let store = FileLogStore(url: url, flushing: { try drive.flush($0) })
        let written = try posts(3, by: &alice)
        try await store.append([written[0]])
        let before = try Data(contentsOf: url)

        drive.refuse(true)
        await #expect(throws: Refused.self) { try await store.append([written[1]]) }

        #expect(try Data(contentsOf: url) == before, "the caller was told this write failed and it is on disk")

        drive.refuse(false)
        try await store.append([written[2]])
        #expect(try await store.loadAll().entries == [written[0], written[2]])
    }
}
