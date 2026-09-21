import CarpenterApp
import CarpenterCloudKit
import CarpenterKeychain
import CloudKit
import CarpenterKit
import CarpenterMedia
import CarpenterUI
import OSLog
import Intents
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

extension SessionStorage {
    static func onDisk() -> SessionStorage {
        let container = Bundle.main.bundleIdentifier ?? "app"
        let directory = StorageLocation.directory(container: container)
        StorageLocation.retireOlderFormats(container: container)
        Diagnostics.sync.notice(
            "storage: \(directory.path, privacy: .public) appGroup=\(AppGroup.available, privacy: .public)")

        return SessionStorage(
            keychain: SystemKeychainStore(service: container, accessGroup: SharedKeychain.group),
            log: FileLogStore(url: directory.appending(path: StorageLocation.logName), backups: .excluded),
            documents: FileDocumentStore(
                url: directory.appending(path: StorageLocation.stateName), backups: .excluded),
            media: FileMediaStore(directory: FileMediaStore.url(inDirectory: directory))
        )
    }
}
