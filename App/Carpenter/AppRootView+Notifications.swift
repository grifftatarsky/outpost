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

// MARK: Permission, the push token, and the badge

extension AppRootView {
    func readNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: notificationsAllowed = nil
        case .authorized, .provisional, .ephemeral: notificationsAllowed = true
        default: notificationsAllowed = false
        }
    }

    func enableMessagePush() async {
        guard session.state == .ready, !messagePushArmed else { return }
        messagePushArmed = true

        if notificationsExplained {
            await PushRegistration.requestMessageAuthorization()
        } else {
            explainingNotifications = true
        }

        guard let cloud = mailbox as? CloudKitMailbox else { return }
        let registered = await cloud.subscribeForInbox()
        let report = await cloud.subscriptionReport()
        Diagnostics.sync.notice(
            """
            push: registered \(registered.count, privacy: .public) subscription(s)
            \(report, privacy: .public)
            """)
    }
    var badgeCount: Int { session.badgeNumber }
    var notificationSettings: NotificationSettings {
        NotificationSettings(
            messaging: session.messagingNotifications,
            outposts: session.outpostNotifications,
            badges: session.badgeChoices,
            systemAllows: notificationsAllowed,
            onMessaging: { await session.setMessagingNotifications($0) },
            onOutposts: { await session.setOutpostNotifications($0) },
            onBadges: { await session.setBadgeChoices($0) },
            onOpenSystemSettings: openSystemSettings)
    }
}
