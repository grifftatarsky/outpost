import CarpenterKit
import SwiftUI

public struct MessagingNotificationsView: View {
    @Environment(\.palette) private var palette

    private let choices: MessagingNotificationChoices
    private let badges: BadgeChoices
    private let onChange: (MessagingNotificationChoices) async -> Void
    private let onBadges: (BadgeChoices) async -> Void
    private let systemAllows: Bool?
    private let onOpenSystemSettings: (() -> Void)?

    public init(
        choices: MessagingNotificationChoices,
        badges: BadgeChoices,
        systemAllows: Bool? = nil,
        onOpenSystemSettings: (() -> Void)? = nil,
        onChange: @escaping (MessagingNotificationChoices) async -> Void,
        onBadges: @escaping (BadgeChoices) async -> Void
    ) {
        self.choices = choices
        self.badges = badges
        self.systemAllows = systemAllows
        self.onOpenSystemSettings = onOpenSystemSettings
        self.onChange = onChange
        self.onBadges = onBadges
    }

    private func change(_ edit: (inout MessagingNotificationChoices) -> Void) {
        var updated = choices
        edit(&updated)
        Task { await onChange(updated) }
    }

    public var body: some View {
        SettingsPage {
            Section {
                SettingsToggle(
                    icon: "bell.badge.fill",
                    title: Text("Tell me about messages", bundle: .module),
                    isOn: Binding(
                        get: { choices.wantsMessages },
                        set: { on in change { $0.wantsMessages = on } }))
            } footer: {
                Text(
                    "Off, nothing arrives when somebody writes to you. What a banner says is kept, so turning this back on returns the answer you gave before.",
                    bundle: .module)
            }
            .groupedRowSurface()

            if choices.wantsMessages {
                Section {
                    ForEach(NotificationLevel.allCases, id: \.self) { level in
                        ChoiceRow(
                            title: Text(level.title, bundle: .module),
                            detail: Text(level.detail, bundle: .module),
                            isSelected: choices.level == level
                        ) { change { $0.level = level } }
                    }
                } header: {
                    Text("What a message says", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "This is what somebody reading over your shoulder can see on a locked screen.",
                        bundle: .module)
                }
                .groupedRowSurface()
            }

            Section {
                SettingsToggle(
                    icon: "person.2.badge.gearshape.fill",
                    title: Text("Tell me about room changes", bundle: .module),
                    isOn: Binding(
                        get: { choices.wantsRoomUpdates },
                        set: { on in change { $0.wantsRoomUpdates = on } }))
            } header: {
                Text("Rooms", bundle: .module).sectionHeading()
            } footer: {
                Text(
                    "Somebody joining or leaving, somebody being removed, a room being renamed, an invitation being answered, or who is allowed to join being changed.\n\nNothing here applies to a solo: two people are already both there, nobody joins one, and the only thing that can happen to its membership ends it rather than changing it.",
                    bundle: .module)
            }
            .groupedRowSurface()

            if choices.wantsRoomUpdates {
                Section {
                    ForEach(RoomUpdateLevel.allCases, id: \.self) { level in
                        ChoiceRow(
                            title: Text(level.example, bundle: .module),
                            detail: Text(level.detail, bundle: .module),
                            isSelected: choices.roomUpdateLevel == level
                        ) { change { $0.roomUpdateLevel = level } }
                    }
                } header: {
                    Text("What a room change says", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "Each of these is the banner you would actually get.", bundle: .module)
                }
                .groupedRowSurface()
            }

            Section {
                SettingsToggle(
                    icon: "app.badge.fill",
                    title: Text("Show on the app icon", bundle: .module),
                    isOn: Binding(
                        get: { badges.messages },
                        set: { on in
                            var updated = badges
                            updated.messages = on
                            Task { await onBadges(updated) }
                        }))
            } header: {
                Text("App icon", bundle: .module).sectionHeading()
            } footer: {
                BadgeMeaningLine(meaning: badges.meaning)
            }
            .groupedRowSurface()

            if systemAllows == false {
                Section {
                    if let onOpenSystemSettings {
                        Button(action: onOpenSystemSettings) {
                            SettingsRow(
                                icon: "gear", tone: .device,
                                title: Text("Turn on notifications", bundle: .module))
                        }
                    }
                } footer: {
                    Text(
                        "Notifications are off for \(Branding.displayName) in Settings, so none of these will arrive until that is turned back on. What you choose here is kept either way.",
                        bundle: .module)
                        .foregroundStyle(palette.destructive)
                }
                .groupedRowSurface()
            }
        }
        .listSurfaceHidden()
        .pageBackground()
        .navigationTitle(Text("Messaging notifications", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
    }
}

extension RoomUpdateLevel {
    public var example: LocalizedStringKey {
        switch self {
        case .whoAndWhere: "Alice has been added to FIFO Squad"
        case .whereOnly: "A new member has been added to FIFO Squad"
        case .whatOnly: "A new member has been added to one of your rooms"
        case .nothing: "New room update"
        }
    }

    public var detail: LocalizedStringKey {
        switch self {
        case .whoAndWhere: "Who it was, and which room."
        case .whereOnly: "Which room, but not who."
        case .whatOnly: "What happened, but not where or to whom."
        case .nothing: "That something changed, and nothing else."
        }
    }
}
