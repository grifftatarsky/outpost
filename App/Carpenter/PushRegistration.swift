import CarpenterApp
import CarpenterKit
import CloudKit
import OSLog
import SwiftUI
import UserNotifications

enum PushRegistration {
    static func requestMessageAuthorization() async {
        Diagnostics.sync.notice("push: about to request message authorization")
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            Diagnostics.sync.notice(
                "push: message authorization \(granted ? "granted" : "refused", privacy: .public)")
        } catch {
            Diagnostics.sync.error(
                "push: could not ask for message authorization: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func setBadge(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }

    static func request() {
        #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
            NSApplication.shared.registerForRemoteNotifications()
        #endif
        Diagnostics.sync.notice("push: asked the system to register")
    }

    static func registered(_ token: Data) {
        Diagnostics.sync.notice(
            "push: registered, token \(Diagnostics.fingerprint(token), privacy: .public)")
    }

    static func failed(_ error: Error) {
        Diagnostics.sync.notice(
            "push: unavailable on this machine — \(error.localizedDescription, privacy: .public)")
    }
}

class PushDesk: NSObject, UNUserNotificationCenterDelegate {
    @MainActor static var viewing: String?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let subscriptionID = CKNotification(
            fromRemoteNotificationDictionary: notification.request.content.userInfo)?
            .subscriptionID
        Diagnostics.sync.notice(
            "push: arrived in the foreground (subscription \(subscriptionID ?? "unknown", privacy: .public))")
        await PushArrivals.shared.arrived()

        return PushPresentation.options(
            forSubscriptionID: subscriptionID,
            thread: notification.request.content.threadIdentifier,
            viewing: PushDesk.viewing)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let thread = response.notification.request.content.threadIdentifier
        Diagnostics.sync.notice(
            "push: opened from a notification (thread \(thread.isEmpty ? "none" : thread, privacy: .public))")
        PushArrivals.shared.open(thread: thread)
        await PushArrivals.shared.arrived()
    }

    fileprivate func handleBackgroundPush() async {
        Diagnostics.sync.notice("push: something arrived (background channel)")
        await PushArrivals.shared.arrived()
    }

    fileprivate func adopt() {
        UNUserNotificationCenter.current().delegate = self
        PushRegistration.request()
    }
}

#if os(iOS)
    final class PushDelegate: PushDesk, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            didReceiveRemoteNotification payload: [AnyHashable: Any]
        ) async -> UIBackgroundFetchResult {
            await handleBackgroundPush()
            return .newData
        }

        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            adopt()
            return true
        }

        func application(
            _ application: UIApplication,
            didRegisterForRemoteNotificationsWithDeviceToken token: Data
        ) {
            PushRegistration.registered(token)
        }

        func application(
            _ application: UIApplication,
            didFailToRegisterForRemoteNotificationsWithError error: Error
        ) {
            PushRegistration.failed(error)
        }
    }
#elseif os(macOS)
    final class PushDelegate: PushDesk, NSApplicationDelegate {
        func application(_ application: NSApplication, didReceiveRemoteNotification payload: [String: Any]) {
            Task { await handleBackgroundPush() }
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            adopt()
        }

        func application(
            _ application: NSApplication,
            didRegisterForRemoteNotificationsWithDeviceToken token: Data
        ) {
            PushRegistration.registered(token)
        }

        func application(
            _ application: NSApplication,
            didFailToRegisterForRemoteNotificationsWithError error: Error
        ) {
            PushRegistration.failed(error)
        }
    }
#endif
