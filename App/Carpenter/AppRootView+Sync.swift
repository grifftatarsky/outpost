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

// MARK: Rounds, the rendezvous, and device sync

extension AppRootView {
    static let foregroundSyncSeconds = 20
    func startDeviceSync() {
        #if DEBUG
            if rig != nil, session.state == .ready {
                RigCodes.leave(session.identityCode(), as: "\(session.viewer.displayName).identity")
            }
        #endif
        guard !UITestMode.isOn, testSession == nil else { return }
        guard case .start(let device) = DeviceSyncDecision.make(
            device: session.thisDeviceID, startedFor: startedSyncFor)
        else { return }
        startedSyncFor = device

        let engine = CloudKitEntrySync(
            container: .default(),
            device: device,
            stateStore: FileDocumentStore(
                url: URL.applicationSupportDirectory
                    .appending(path: Bundle.main.bundleIdentifier ?? "app", directoryHint: .isDirectory)
                    .appending(path: "sync-engine.json")))

        deviceSync = engine
        session.syncDevices(through: engine)
    }
    func syncNow() async {
        guard !UITestMode.isOn, !switchingWorld else { return }
        if syncing {
            syncAgain = true
            return
        }
        syncing = true
        defer { syncing = false }

        if testSession == nil {
            let held = await CloudKitHold.isHeld(.default())
            session.noteICloudHold(held)
            if held { return }
        }

        let outcome = await SyncRound.run(
            deathmark: { await obeyDeathmark() },
            deviceSync: { await session.refreshDeviceSync() },
            mailbox: {
                guard session.enrolment != nil else { return }

                do {
                    _ = try await session.sync(through: mailbox, media: cloud)
                } catch where CloudKitHold.isSecurityHold(error) {
                    session.noteICloudHold(true)
                    throw error
                }
                if let cloud = mailbox as? CloudKitMailbox, let pairs = session.pairs() {
                    await cloud.retireOldOutbox(whenEveryoneHasMovedAmong: session.peersLastRound, in: pairs)
                }
            },
        )

        if let syncedAt = outcome.syncedAt { lastSync = syncedAt }
        mediaLoader?.reconsiderAsked()
        mediaBytes = await session.mediaByteCount()
        await collectSharedPhotos()
        await reportFocusNow()
        FocusFilterStore.shared.writeRooms(
            session.rooms.map { FocusFilterStore.RoomEntry(id: $0.id, name: $0.name) })

        if outcome.deviceSyncFailed { Diagnostics.sync.error("device sync refresh failed") }
        if outcome.mailboxFailed { Diagnostics.sync.error("sync failed") }

        if let url = DiagnosticsExport.documentsURL {
            Task.detached(priority: .utility) { DiagnosticsExport.write(to: url) }
        }

        if session.metSomebodyNew { syncAgain = true }

        if syncAgain {
            syncAgain = false
            syncing = false
            await syncNow()
        }
    }
}
