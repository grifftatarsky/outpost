import CarpenterKit
import SwiftUI

public struct NotificationsView: View {
    @Environment(\.palette) private var palette

    private let settings: NotificationSettings

    public init(settings: NotificationSettings) {
        self.settings = settings
    }

    public var body: some View {
        List {
            Section {
                // COPY BEGIN 8246d001 [NEEDS HUMAN REVIEW]
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
                // COPY END 8246d001
            } footer: {
                BadgeMeaningLine(meaning: settings.badges.meaning)
            }
            .groupedRowSurface()

            // COPY BEGIN 0728e4fa [NEEDS HUMAN REVIEW]
            Section {
            } footer: {
                Text(
                    "Alerts about your own settings — a check-up, your history, your recovery key — only ever appear inside the app, on the You tab. They never count toward the number on your app icon, because that number means somebody is trying to reach you.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END 0728e4fa

            // COPY BEGIN dd400255 [NEEDS HUMAN REVIEW]
            Section {
            } footer: {
                Text(
                    "A Focus silences these like anything else. If you would rather they came through, you can allow this app in that Focus, in the Settings app under Focus. That is a choice on your phone, not something anybody writing to you can decide.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END dd400255
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN f79f95df [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Notifications", bundle: .module))
        // COPY END f79f95df
        .toolbarTitleDisplayMode(.inline)
    }
}

public struct NotificationSettings {
    public let messaging: MessagingNotificationChoices
    public let outposts: OutpostNotificationChoices
    public let badges: BadgeChoices
    public let systemAllows: Bool?
    public let onMessaging: (MessagingNotificationChoices) async -> Void
    public let onOutposts: (OutpostNotificationChoices) async -> Void
    public let onBadges: (BadgeChoices) async -> Void
    public let onOpenSystemSettings: (() -> Void)?

    public init(
        messaging: MessagingNotificationChoices,
        outposts: OutpostNotificationChoices,
        badges: BadgeChoices,
        systemAllows: Bool?,
        onMessaging: @escaping (MessagingNotificationChoices) async -> Void,
        onOutposts: @escaping (OutpostNotificationChoices) async -> Void,
        onBadges: @escaping (BadgeChoices) async -> Void,
        onOpenSystemSettings: (() -> Void)? = nil
    ) {
        self.messaging = messaging
        self.outposts = outposts
        self.badges = badges
        self.systemAllows = systemAllows
        self.onMessaging = onMessaging
        self.onOutposts = onOutposts
        self.onBadges = onBadges
        self.onOpenSystemSettings = onOpenSystemSettings
    }
}
