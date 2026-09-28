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
    static let mainProtection = ProtectionDial()

    static func onDisk(profile: TestProfile? = nil) -> SessionStorage {
        let container = TestProfileWorld.container(for: profile)
        let directory = StorageLocation.directory(container: container)
        Diagnostics.sync.notice(
            "storage: \(directory.path, privacy: .public) appGroup=\(AppGroup.available, privacy: .public)")

        let protection = profile == nil ? mainProtection : ProtectionDial()
        let system = SystemKeychainStore(
            service: container, accessGroup: SharedKeychain.group, protection: protection)
        let keychain: any KeychainStore = profile == nil ? system : DeviceOnlyKeychainStore(system)

        return SessionStorage(
            keychain: keychain,
            log: FileLogStore(url: directory.appending(path: StorageLocation.logName), protection: protection),
            documents: FileDocumentStore(
                url: directory.appending(path: StorageLocation.stateName), protection: protection),
            media: FileMediaStore(directory: FileMediaStore.url(inDirectory: directory), protection: protection),
            protection: protection,
            locations: keptLocations(container: container, directory: directory, shared: profile == nil)
        )
    }

    private static func keptLocations(container: String, directory: URL, shared: Bool) -> [URL] {
        let fallback = StorageLocation.fallback(container: container)
        let own = [
            directory, fallback.appending(path: StorageLocation.logName),
            fallback.appending(path: StorageLocation.stateName),
        ]
        guard shared else { return own }
        return own + [FocusFilterStore.directory, FileManager.default.temporaryDirectory].compactMap { $0 }
    }
}
