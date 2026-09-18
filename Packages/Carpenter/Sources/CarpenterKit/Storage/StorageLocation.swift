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
    public static let mailboxDirectoryName = "mailbox-directory.json"
    public static let avatarName = "avatar.jpg"
    public static let outpostAvatarName = "outpost-avatar.jpg"
    public static let personAvatarsName = "people-avatars"

    public static func directory(
        container: String,
        appGroup: String? = AppGroup.identifier,
        fileManager: FileManager = .default
    ) -> URL {
        let fallback = URL.applicationSupportDirectory
            .appending(path: container, directoryHint: .isDirectory)

        guard let appGroup,
            let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return fallback }

        let shared = group.appending(path: container, directoryHint: .isDirectory)
        migrate(from: fallback, to: shared, using: fileManager)
        return shared
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
