import CarpenterKit
import SwiftUI

public struct NotificationsView: View {
    @Environment(\.palette) private var palette

    private let settings: NotificationSettings

    public init(settings: NotificationSettings) {
        self.settings = settings
    }

    public var body: some View {
        SettingsPage {
            Section {
                NavigationLink {
                    MessagingNotificationsView(
                        choices: settings.messaging, badges: settings.badges,
                        systemAllows: settings.systemAllows,
                        onOpenSystemSettings: settings.onOpenSystemSettings,
                        onChange: settings.onMessaging, onBadges: settings.onBadges)
                } label: {
                    SettingsRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: Text("Messaging", bundle: .module),
                        detail: settings.messaging.wantsMessages
                            ? Text(settings.messaging.level.shortTitle, bundle: .module)
                            : Text("Off", bundle: .module))
                }
                NavigationLink {
                    OutpostNotificationsView(
                        choices: settings.outposts, badges: settings.badges,
                        systemAllows: settings.systemAllows,
                        onOpenSystemSettings: settings.onOpenSystemSettings,
                        onChange: settings.onOutposts, onBadges: settings.onBadges)
                } label: {
                    SettingsRow(
                        icon: "rectangle.stack.badge.person.crop.fill",
                        title: Text("Outposts", bundle: .module),
                        detail: settings.outposts.wantsAnything
                            ? Text("\(settings.outposts.wantedCount) of 5", bundle: .module)
                            : Text("Off", bundle: .module))
                }
            } footer: {
                BadgeMeaningLine(meaning: settings.badges.meaning)
            }
            .groupedRowSurface()

            Section {
            } footer: {
                Text(
                    "Alerts about your own settings — a check-up, your history, your recovery key — only ever appear inside the app, on the You tab. They never count toward the number on your app icon, because that number means somebody is trying to reach you.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
            } footer: {
                Text(
                    "A Focus silences these like anything else. If you would rather they came through, you can allow this app in that Focus, in the Settings app under Focus. That is a choice on your phone, not something anybody writing to you can decide.",
                    bundle: .module)
            }
            .groupedRowSurface()
        }
        .listSurfaceHidden()
        .pageBackground()
        .navigationTitle(Text("Notifications", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
    }
}

public struct NotificationSettings {
    public let messaging: MessagingNotificationChoices
    public let outposts: OutpostNotificationChoices
    public let badges: BadgeChoices
    public let systemAllows: Bool?
    public let systemShowsBadges: Bool?
    public let onMessaging: (MessagingNotificationChoices) async -> Void
    public let onOutposts: (OutpostNotificationChoices) async -> Void
    public let onBadges: (BadgeChoices) async -> Void
    public let onOpenSystemSettings: (() -> Void)?

    public init(
        messaging: MessagingNotificationChoices,
        outposts: OutpostNotificationChoices,
        badges: BadgeChoices,
        systemAllows: Bool?,
        systemShowsBadges: Bool?,
        onMessaging: @escaping (MessagingNotificationChoices) async -> Void,
        onOutposts: @escaping (OutpostNotificationChoices) async -> Void,
        onBadges: @escaping (BadgeChoices) async -> Void,
        onOpenSystemSettings: (() -> Void)? = nil
    ) {
        self.messaging = messaging
        self.outposts = outposts
        self.badges = badges
        self.systemAllows = systemAllows
        self.systemShowsBadges = systemShowsBadges
        self.onMessaging = onMessaging
        self.onOutposts = onOutposts
        self.onBadges = onBadges
        self.onOpenSystemSettings = onOpenSystemSettings
    }
}
