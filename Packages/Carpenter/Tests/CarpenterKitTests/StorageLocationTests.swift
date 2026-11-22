import CarpenterKit
import Foundation
import Testing

@Suite("Where the store is kept", .tags(.storage))
struct StorageLocationTests {
    private func temp() -> URL {
        TestScratch.root.appending(
            path: "storageloc-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

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
