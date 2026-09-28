import Foundation

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

        guard let appGroup,
            let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else {
            leaveOutOfBackups(fallback, using: fileManager)
            return fallback
        }

        let shared = group.appending(path: container, directoryHint: .isDirectory)
        migrate(from: fallback, to: shared, using: fileManager)
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

    public static func migrate(from: URL, to: URL, using fileManager: FileManager) {
        do {
            try fileManager.createDirectory(at: to, withIntermediateDirectories: true)
        } catch {
            Diagnostics.sync.error(
                "storage: could not make the shared container directory (\(String(describing: error), privacy: .public))")
            return
        }
        for name in [logName, stateName] {
            let source = from.appending(path: name)
            let destination = to.appending(path: name)
            guard fileManager.fileExists(atPath: source.path),
                !fileManager.fileExists(atPath: destination.path)
            else { continue }
            do {
                try fileManager.copyItem(at: source, to: destination)
            } catch {
                Diagnostics.sync.error(
                    "storage: could not copy \(name, privacy: .public) into the shared container; still reading the app's own copy (\(String(describing: error), privacy: .public))")
            }
        }
    }
}
