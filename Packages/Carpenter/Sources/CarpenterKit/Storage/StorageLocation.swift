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
        let directory = shared ?? fallback
        leaveOutOfBackups(directory, using: fileManager)
        return directory
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
}
