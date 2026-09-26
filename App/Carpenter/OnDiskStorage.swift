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
    static func onDisk(profile: TestProfile? = nil) -> SessionStorage {
        let container = TestProfileWorld.container(for: profile)
        let directory = StorageLocation.directory(container: container)
        Diagnostics.sync.notice(
            "storage: \(directory.path, privacy: .public) appGroup=\(AppGroup.available, privacy: .public)")

        let system = SystemKeychainStore(service: container, accessGroup: SharedKeychain.group)
        let keychain: any KeychainStore = profile == nil ? system : DeviceOnlyKeychainStore(system)

        return SessionStorage(
            keychain: keychain,
            log: FileLogStore(url: directory.appending(path: StorageLocation.logName)),
            documents: FileDocumentStore(url: directory.appending(path: StorageLocation.stateName)),
            media: FileMediaStore(directory: FileMediaStore.url(inDirectory: directory))
        )
    }
}
