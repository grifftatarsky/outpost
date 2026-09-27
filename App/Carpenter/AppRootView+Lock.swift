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

        func show(_ controller: AppLockController, onForget: @escaping () async -> Void) {
            guard window == nil,
                let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState != .unattached })
            else { return }
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = UIHostingController(
                rootView: AppLockScreen(controller: controller, onForget: onForget).themed(.default))
            window.makeKeyAndVisible()
            self.window = window
        }

        func hide() {
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
                onLock: { lock in
                    guard await appLock.turnOn(lock) else { return false }
                    lockOffered = true
                    return true
                },
                onNotNow: { lockOffered = true })
        }
        .themed(.default)
    }
}
