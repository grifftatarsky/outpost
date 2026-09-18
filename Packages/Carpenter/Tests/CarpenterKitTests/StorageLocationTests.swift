import CarpenterKit
import Foundation
import Testing

@Suite("App Group storage migration")
struct StorageLocationTests {
    private func temp() -> URL {
        URL.temporaryDirectory.appending(
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
