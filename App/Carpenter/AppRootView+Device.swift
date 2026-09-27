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

// MARK: This device: where it keeps things, and erasing it

extension AppRootView {
    static var deviceName: String {
        #if os(macOS)
            return "Mac"
        #else
            return UIDevice.current.model
        #endif
    }

    func applyAppIcon(_ choice: AppIconChoice) async {
        await AppIconSwitching.apply(choice)
    }

    static func mailboxDirectoryStore() -> any DocumentStore {
        let container = Bundle.main.bundleIdentifier ?? "app"
        return FileDocumentStore(
            url: StorageLocation.directory(container: container)
                .appending(path: StorageLocation.mailboxDirectoryName))
    }

    static var registrationProbeURL: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "app", directoryHint: .isDirectory)
            .appending(path: "registration-probe.json")
    }

    #if DEBUG
    func checkMailbox() async {
        guard let cloud = mailbox as? CloudKitMailbox else {
            cloudTrouble = "Not running on the CloudKit mailbox."
            return
        }
        cloudTrouble = await cloud.roundTrip()
    }

    func rotateMailboxShare() async {
        do {
            try await cloud.eraseOutbox()
            try await cloud.prepare()
            let url = try await cloud.shareURL()
            lastRendezvous = Date()
            Diagnostics.sync.notice(
                "debug: rotated the mailbox share; the next offer carries a new URL (…\(String(url.absoluteString.suffix(6)), privacy: .public))")
        } catch {
            Diagnostics.sync.error(
                "debug: could not rotate the mailbox share: \(String(describing: error), privacy: .public)")
        }
    }

    #endif

    func wipe(leavingDeathmark: Bool = true) async throws {
        if leavingDeathmark, let board = deathmarkBoard, session.enrolment != nil {
            try await session.leaveDeathmark(on: board)
        }
        if testSession == nil {
            try await eraseSharedDeviceState()
        }
        deviceSync = nil
        startedSyncFor = nil

        if let cloud = mailbox as? CloudKitMailbox {
            try await cloud.eraseOutbox()
        }
        try await deathmarkBoard?.eraseEverythingElse()

        await eraseThisDevice()
    }

    func obeyDeathmark() async -> Bool {
        guard let board = deathmarkBoard else { return false }
        await finishPendingGlobalErase(on: board)
        guard session.enrolment != nil, await session.obeyDeathmark(on: board) == .eraseThisDevice else {
            return false
        }
        await eraseThisDevice()
        return true
    }

    func eraseEverywhereOrLater() async {
        if (try? await wipe()) != nil { return }
        if let prepared = try? session.prepareDeathmark(), let data = try? JSONEncoder().encode(prepared) {
            UserDefaults.standard.set(data, forKey: Self.pendingDeathmarkKey)
        }
        await eraseThisDevice()
        if let board = deathmarkBoard { await finishPendingGlobalErase(on: board) }
    }

    func finishPendingGlobalErase(on board: CloudKitDeathmarkBoard) async {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingDeathmarkKey),
            let prepared = try? JSONDecoder().decode(PreparedDeathmark.self, from: data)
        else { return }
        do {
            try await prepared.post(on: board)
            try await board.eraseEverythingElse()
            UserDefaults.standard.removeObject(forKey: Self.pendingDeathmarkKey)
            Diagnostics.identity.notice("deathmark: the erase that could not reach iCloud has now reached it")
        } catch {
            Diagnostics.identity.error(
                "deathmark: still can't reach iCloud to finish erasing (\(String(describing: error), privacy: .public))")
        }
    }

    static let pendingDeathmarkKey = "deathmark.pending"

    private func eraseSharedDeviceState() async throws {
        if let deviceSync {
            try await deviceSync.eraseSharedState()
        } else {
            let engine = CloudKitEntrySync(
                container: .default(),
                device: session.enrolment?.device.id ?? DeviceID(rawValue: Data()),
                stateStore: FileDocumentStore(url: Self.engineStateURL))
            try await engine.eraseSharedState()
        }
    }

    func forgetOldSiriDonations() async {
        guard !siriDonationsForgotten else { return }
        do {
            try await INInteraction.deleteAll()
            siriDonationsForgotten = true
        } catch {
            Diagnostics.sync.error(
                "siri: could not delete what earlier builds donated (\(String(describing: error), privacy: .public))")
        }
    }

    func eraseThisDevice() async {
        deviceSync = nil
        startedSyncFor = nil
        askingOutpostNotifications = false
        explainingNotifications = false
        redeeming = false
        restoring = false
        try? await INInteraction.deleteAll()

        let container = worldContainer
        try? await SystemKeychainStore(
            service: container, accessGroup: SharedKeychain.group
        ).removeAll()

        try? FileManager.default.removeItem(
            at: URL.applicationSupportDirectory.appending(
                path: container, directoryHint: .isDirectory))
        try? FileManager.default.removeItem(at: StorageLocation.directory(container: container))
        FocusFilterStore.shared.writeRooms([])

        do {
            try FileManager.default.removeItem(
                at: FileMediaStore.url(
                    inDirectory: StorageLocation.directory(container: container)))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
        } catch {
            Diagnostics.sync.error(
                "wipe: could not remove the photos (\(String(describing: error), privacy: .public))")
        }

        do {
            try avatarStore.remove()
        } catch {
            Diagnostics.sync.error(
                "wipe: could not remove the avatar (\(String(describing: error), privacy: .public))")
        }
        ownAvatar = nil
        do {
            try personAvatarStore.removeAll()
        } catch {
            Diagnostics.sync.error(
                "wipe: could not remove the photos kept for other people (\(String(describing: error), privacy: .public))")
        }
        do {
            try outpostAvatarStore.remove()
        } catch {
            Diagnostics.sync.error(
                "wipe: could not remove the Outpost picture (\(String(describing: error), privacy: .public))")
        }
        ownOutpostAvatar = nil
        personAvatars = [:]
        sharedAvatars = [:]
        outpostAvatars = [:]

        session = AppSession(storage: .onDisk(profile: testSession?.profile), clock: UITestMode.clock)
        session.enforcesDenyList = safety.blocksKnownAbusers
        mediaLoader = makeMediaLoader()
        session.checkAccount(with: accountRegistry)
        await session.load()
        await session.settleRegistration()
    }

    static var engineStateURL: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "app", directoryHint: .isDirectory)
            .appending(path: "sync-engine.json")
    }
    // COPY BEGIN 241275d8 [NEEDS HUMAN REVIEW]
    func nuke() async {
        await attempting(
            String(localized: "This account was not cleared"), "nuke account"
        ) { try await wipe() }
    }
    // COPY END 241275d8
    func openSystemSettings() {
        #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        #elseif os(macOS)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(url)
            }
        #endif
    }
}
