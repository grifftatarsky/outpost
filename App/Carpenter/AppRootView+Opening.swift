import CarpenterApp
import CarpenterKit
import CarpenterUI
import SwiftUI
import os

#if canImport(UIKit)
    import UIKit
#endif

// MARK: Opening the session, and waiting for the phone to unlock

extension AppRootView {
    func openSession() async {
        #if os(iOS)
            session.phoneLocked(!UIApplication.shared.isProtectedDataAvailable)
        #endif
        await session.readProtection()
        await session.load()
        Task { await protectWhatIsKept() }
    }

    func finishOpening() async {
        guard !session.waitsForUnlock else { return }
        loadAvatars()
        resolveOwnOutpostAvatar()
        await session.settleRegistration()
        await session.nameThisDeviceIfUnnamed(HardwareName.ofThisDevice)
        startDeviceSync()

        var delay = 1
        while session.isWaitingForAnIdentity {
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { break }
            if await session.recheckForSyncedIdentity() { break }
            delay = min(delay * 2, 30)
        }
    }

    func reopenIfUnlocked() async {
        guard session.phoneIsLocked else { return }
        #if os(iOS)
            guard UIApplication.shared.isProtectedDataAvailable else { return }
        #endif
        session.phoneLocked(false)
        let waited = session.waitsForUnlock
        await session.readProtection()
        Task { await protectWhatIsKept() }
        if waited {
            await session.load()
            await finishOpening()
        }
        await syncNow()
    }

    var deviceSecurity: DeviceSecuritySetting {
        DeviceSecuritySetting(isOn: session.sealsWhileLocked) { [session] on in
            do {
                try await session.sealWhileLocked(on)
                return nil
            } catch {
                return SessionProblem.sentence(for: error)
            }
        }
    }

    private func protectWhatIsKept() async {
        do {
            try await session.applyProtection()
        } catch {
            Diagnostics.identity.error(
                "storage: not everything was protected; trying again next time (\(String(describing: error), privacy: .public))")
        }
    }
}
