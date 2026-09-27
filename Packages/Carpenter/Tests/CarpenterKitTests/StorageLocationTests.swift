import CarpenterKit
import Foundation
import Testing

@Suite("App Group storage migration")
struct StorageLocationTests {
    private func temp() -> URL {
        TestScratch.root.appending(
            path: "storageloc-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test("Copies existing files across, non-destructively")
    func copiesAcross() throws {
        let fm = FileManager.default
        let from = temp(), to = temp()
        try fm.createDirectory(at: from, withIntermediateDirectories: true)
        let log = from.appending(path: StorageLocation.logName)
        try Data("history".utf8).write(to: log)
        defer { try? fm.removeItem(at: from); try? fm.removeItem(at: to) }

        StorageLocation.migrate(from: from, to: to, using: fm)

        #expect(fm.fileExists(atPath: to.appending(path: StorageLocation.logName).path))
        #expect(fm.fileExists(atPath: log.path), "the original must remain as a fallback")
        let copied = try Data(contentsOf: to.appending(path: StorageLocation.logName))
        #expect(String(decoding: copied, as: UTF8.self) == "history")
    }

    @Test("Never overwrites a file already in the destination")
    func doesNotOverwrite() throws {
        let fm = FileManager.default
        let from = temp(), to = temp()
        try fm.createDirectory(at: from, withIntermediateDirectories: true)
        try fm.createDirectory(at: to, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: from.appending(path: StorageLocation.logName))
        try Data("current".utf8).write(to: to.appending(path: StorageLocation.logName))
        defer { try? fm.removeItem(at: from); try? fm.removeItem(at: to) }

        StorageLocation.migrate(from: from, to: to, using: fm)

        let kept = try Data(contentsOf: to.appending(path: StorageLocation.logName))
        #expect(
            String(decoding: kept, as: UTF8.self) == "current",
            "migration overwrote newer data in the destination")
    }
}

@Suite("What the app keeps stays out of backups")
struct StoreLeftOutOfBackupsTests {
    @Test("The store's directory is marked for leaving out of backups, and a folder beside it is not")
    func theStoreIsLeftOut() throws {
        let root = TestScratch.root.appending(path: "backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        let beside = root.appending(path: "beside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: beside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = StorageLocation.directory(container: "world", appGroup: nil, root: root)

        #expect(store == root.appending(path: "world", directoryHint: .isDirectory))
        #expect(try store.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try beside.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup != true)
    }

    @Test("A directory that was already left out stays left out after it is asked for again")
    func askingAgainKeepsIt() throws {
        let root = TestScratch.root.appending(path: "backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = StorageLocation.directory(container: "world", appGroup: nil, root: root)
        var store = root.appending(path: "world", directoryHint: .isDirectory)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try store.setResourceValues(values)

        _ = StorageLocation.directory(container: "world", appGroup: nil, root: root)

        #expect(try store.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
}
