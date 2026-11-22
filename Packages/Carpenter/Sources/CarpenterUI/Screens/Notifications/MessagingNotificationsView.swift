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
        List {
            // COPY BEGIN 409ce86f [NEEDS HUMAN REVIEW]
            Section {
                SettingsToggle(
                    icon: "bell.badge.fill",
                    title: Text("Tell me about messages", bundle: .module),
                    isOn: Binding(
                        get: { choices.wantsMessages },
                        set: { on in change { $0.wantsMessages = on } }))
            } footer: {
                Text(
                    "When this is off, you get no notification when somebody writes to you. Your banner choices are kept for when you turn it back on.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END 409ce86f

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
                    // COPY BEGIN e1a8506a [NEEDS HUMAN REVIEW]
                    Text("What a message says", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "This is what somebody reading over your shoulder can see on a locked screen.",
                        bundle: .module)
                    // COPY END e1a8506a
                }
                .groupedRowSurface()
            }

            // COPY BEGIN 5b69624a [NEEDS HUMAN REVIEW]
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
            // COPY END 5b69624a

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
                    // COPY BEGIN b5facd29 [NEEDS HUMAN REVIEW]
                    Text("What a room change says", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "Each of these is the banner you would actually get.", bundle: .module)
                    // COPY END b5facd29
                }
                .groupedRowSurface()
            }

            AppIconBadgeSection(isOn: badges.messages, meaning: badges.meaning) { on in
                var updated = badges
                updated.messages = on
                Task { await onBadges(updated) }
            }

            if systemAllows == false {
                NotificationsOffSection(onOpenSystemSettings: onOpenSystemSettings)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN b7e217e5 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Messaging notifications", bundle: .module))
        // COPY END b7e217e5
        .toolbarTitleDisplayMode(.inline)
    }
}

extension RoomUpdateLevel {
    // COPY BEGIN 00c57a6d [NEEDS HUMAN REVIEW]
    public var example: LocalizedStringKey {
        switch self {
        case .whoAndWhere: "Alice has been added to FIFO Squad"
        case .whereOnly: "A new member has been added to FIFO Squad"
        case .whatOnly: "A new member has been added to one of your rooms"
        case .nothing: "New room update"
        }
    }
    // COPY END 00c57a6d

    // COPY BEGIN a68d11ea [NEEDS HUMAN REVIEW]
    public var detail: LocalizedStringKey {
        switch self {
        case .whoAndWhere: "Who it was, and which room."
        case .whereOnly: "Which room, but not who."
        case .whatOnly: "What happened, but not where or to whom."
        case .nothing: "That something changed, and nothing else."
        }
    }
    // COPY END a68d11ea
}

#if DEBUG
    #Preview("Messaging notifications") {
        NavigationStack {
            MessagingNotificationsView(
                choices: .default, badges: BadgeChoices(messages: true, outposts: true), systemAllows: true,
                onChange: { _ in }, onBadges: { _ in })
        }
        .themed(.default)
    }
#endif
