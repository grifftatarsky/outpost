import Foundation
import os

public enum AppGroup {
    public static let identifier = "group.com.microgpt.carpenter"

    public static var available: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }
}

public enum StorageLocation {
    public static let logName = "log.carpenter"
    public static let stateName = "state.json"
    public static let avatarName = "avatar.jpg"
    public static let outpostAvatarName = "outpost-avatar.jpg"
    public static let personAvatarsName = "people-avatars"

    public static func fallback(container: String, root: URL = .applicationSupportDirectory) -> URL {
        root.appending(path: container, directoryHint: .isDirectory)
    }

    public static func directory(
        container: String,
        appGroup: String? = AppGroup.identifier,
        root: URL = .applicationSupportDirectory,
        fileManager: FileManager = .default
    ) -> URL {
        let fallback = Self.fallback(container: container, root: root)
        let shared = appGroup
            .flatMap { fileManager.containerURL(forSecurityApplicationGroupIdentifier: $0) }?
            .appending(path: container, directoryHint: .isDirectory)
        return resolved(fallback: fallback, shared: shared, using: fileManager)
    }

    public static func resolved(fallback: URL, shared: URL?, using fileManager: FileManager = .default) -> URL {
        guard let shared, migrate(from: fallback, to: shared, using: fileManager) else {
            leaveOutOfBackups(fallback, using: fileManager)
            return fallback
        }
        leaveOutOfBackups(shared, using: fileManager)
        if fileManager.fileExists(atPath: fallback.path) { leaveOutOfBackups(fallback, using: fileManager) }
        return shared
    }

    public static func leaveOutOfBackups(_ directory: URL, using fileManager: FileManager = .default) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var target = directory
            if try target.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true {
                return
            }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try target.setResourceValues(values)
        } catch {
            Diagnostics.sync.error(
                "storage: could not leave the store out of backups (\(String(describing: error), privacy: .public))")
        }
    }

    @discardableResult
    public static func migrate(from: URL, to: URL, using fileManager: FileManager) -> Bool {
        do {
            try fileManager.createDirectory(at: to, withIntermediateDirectories: true)
        } catch {
            Diagnostics.sync.error(
                "storage: could not make the shared container directory; reading the app's own copy (\(String(describing: error), privacy: .public))")
            return false
        }
        var placed: [URL] = []
        var settled: [URL] = []
        for name in [logName, stateName] {
            let source = from.appending(path: name)
            let destination = to.appending(path: name)
            guard isFile(source, using: fileManager) else { continue }
            if isFile(destination, using: fileManager) {
                settled.append(source)
                continue
            }
            do {
                try bringAcross(source, to: destination, using: fileManager)
                placed.append(destination)
                settled.append(source)
            } catch where isFile(destination, using: fileManager) {
                settled.append(source)
            } catch {
                for partial in placed { try? fileManager.removeItem(at: partial) }
                Diagnostics.sync.error(
                    "storage: could not copy \(name, privacy: .public) into the shared container; reading the app's own copy (\(String(describing: error), privacy: .public))")
                return false
            }
        }
        for source in settled {
            do {
                try fileManager.removeItem(at: source)
            } catch {
                Diagnostics.sync.error(
                    "storage: could not delete the copy left from before the shared container (\(String(describing: error), privacy: .public))")
            }
        }
        return true
    }

    private static func bringAcross(_ source: URL, to destination: URL, using fileManager: FileManager) throws {
        let staged = destination.deletingLastPathComponent()
            .appending(path: ".\(destination.lastPathComponent)-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staged) }
        try fileManager.copyItem(at: source, to: staged)
        guard fileManager.contentsEqual(atPath: source.path, andPath: staged.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try fileManager.moveItem(at: staged, to: destination)
    }

    private static func isFile(_ url: URL, using fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}
