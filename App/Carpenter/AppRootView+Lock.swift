import CarpenterApp
import CarpenterKeychain
import CarpenterKit
import CarpenterUI
import SwiftUI

#if canImport(UIKit)
    import UIKit

    @MainActor
    final class LockWindow {
        static let shared = LockWindow()

        private var window: UIWindow?
        private var covered: [UIWindow] = []

        func show(_ controller: AppLockController, onForget: @escaping () async -> Void) {
            guard window == nil,
                let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState != .unattached })
            else { return }
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.accessibilityViewIsModal = true
            window.rootViewController = UIHostingController(
                rootView: AppLockScreen(controller: controller, onForget: onForget).themed(.default))
            covered = scene.windows.filter { $0 !== window && !$0.accessibilityElementsHidden }
            for other in covered { other.accessibilityElementsHidden = true }
            window.makeKeyAndVisible()
            self.window = window
        }

        func hide() {
            for other in covered { other.accessibilityElementsHidden = false }
            covered = []
            window?.isHidden = true
            window = nil
        }
    }
#endif

extension AppRootView {
    static let appLockStore = AppLockStore(
        keychain: SystemKeychainStore(
            service: TestProfileWorld.container(for: nil), accessGroup: SharedKeychain.group))

    func coverForLock(_ covered: Bool) {
        #if canImport(UIKit)
            if covered {
                LockWindow.shared.show(appLock) { await forgetTheLock() }
            } else {
                LockWindow.shared.hide()
            }
        #endif
    }

    func configureAppLock() {
        appLock.onEraseEverywhere = { await eraseEverywhereFromTheLock() }
        appLock.recovery = RecoveryKeyAccess(
            isSaved: { session.recoveryKeySavedAt != nil },
            unsaved: { session.recoveryKeyText().map { ($0, session.recoveryKeyFingerprint ?? "") } },
            markSaved: { await session.noteRecoveryKeySaved() },
            opens: { session.recoveryKeyOpens($0) })
        appLock.notificationPrivacy = NotificationPrivacy(
            reveals: { notificationsAllowed == true && session.notificationsRevealMore },
            makePrivate: { await session.makeNotificationsPrivate() })
    }

    func eraseEverywhereFromTheLock() async {
        await nuke()
        try? await Self.appLockStore.remove()
        appLock.forget()
        lockOffered = false
    }

    var notificationsStep: some View {
        PermissionExplainerView(
            .notifications,
            onContinue: {
                notificationsExplained = true
                Task {
                    await PushRegistration.requestMessageAuthorization()
                    await readNotificationPermission()
                    if notificationsAllowed == true, !session.hasAnsweredOutpostNotifications {
                        askingOutpostNotifications = true
                    }
                }
            },
            onDecline: { notificationsExplained = true }
        )
        .themed(.default)
    }

    func forgetTheLock() async {
        await eraseThisDevice()
        try? await Self.appLockStore.remove()
        appLock.forget()
        lockOffered = false
    }

    var lockOffer: some View {
        NavigationStack {
            AppLockSetupView(
                biometricName: appLock.biometricName,
                revealsNotifications: { appLock.notificationPrivacy?.reveals() ?? false },
                onLock: { lock in
                    lockOfferOpen = true
                    return await appLock.turnOn(lock)
                },
                onMakeNotificationsPrivate: { await appLock.notificationPrivacy?.makePrivate() },
                onDone: {
                    lockOffered = true
                    lockOfferOpen = false
                },
                onNotNow: { lockOffered = true })
        }
        .themed(.default)
    }
}
