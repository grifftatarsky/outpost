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

        let protection = profile == nil ? ProtectionDial.main : ProtectionDial()
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
            locations: keptLocations(container: container, directory: directory, shared: profile == nil),
            settings: profile == nil ? keptSettings : []
        )
    }

    private static func keptLocations(container: String, directory: URL, shared: Bool) -> [URL] {
        let own = [directory, StorageLocation.fallback(container: container)]
        guard shared else { return own }
        return own + [FocusFilterStore.directory, ScratchSpace.shared.directory].compactMap { $0 }
    }

    private static let keptSettings = [
        KeptSetting(key: MediaLoader.revealedKey),
        KeptSetting(suite: AppGroup.identifier, key: FocusFilterStore.filterKey),
    ]
}
