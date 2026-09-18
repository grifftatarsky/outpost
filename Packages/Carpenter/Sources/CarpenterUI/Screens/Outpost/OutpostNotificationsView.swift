import CarpenterKit
import SwiftUI

public struct OutpostNotificationsView: View {
    @Environment(\.palette) private var palette

    private let choices: OutpostNotificationChoices
    private let badges: BadgeChoices
    private let onChange: (OutpostNotificationChoices) async -> Void
    private let onBadges: (BadgeChoices) async -> Void
    private let systemAllows: Bool?
    private let onOpenSystemSettings: (() -> Void)?

    public init(
        choices: OutpostNotificationChoices,
        badges: BadgeChoices,
        systemAllows: Bool? = nil,
        onOpenSystemSettings: (() -> Void)? = nil,
        onChange: @escaping (OutpostNotificationChoices) async -> Void,
        onBadges: @escaping (BadgeChoices) async -> Void
    ) {
        self.choices = choices
        self.badges = badges
        self.systemAllows = systemAllows
        self.onOpenSystemSettings = onOpenSystemSettings
        self.onChange = onChange
        self.onBadges = onBadges
    }

    private func binding(_ kind: OutpostNotificationChoices.Kind) -> Binding<Bool> {
        Binding(
            get: { choices.wants(kind) },
            set: { wanted in
                var updated = choices
                updated[keyPath: kind.path] = wanted
                Task { await onChange(updated) }
            })
    }

    private func chooseNewPosts(_ answer: NewPostNotifications) {
        var updated = choices
        updated.newPosts = answer
        Task { await onChange(updated) }
    }

    public var body: some View {
        SettingsPage {
            Section {
                ChoiceRow(
                    title: Text("All posts", bundle: .module),
                    detail: Text(
                        "Every Outpost you can read, whatever each one is set to.", bundle: .module),
                    isSelected: choices.newPosts == .all
                ) { chooseNewPosts(.all) }

                ChoiceRow(
                    title: Text("By Outpost", bundle: .module),
                    detail: Text(
                        "Only the ones you have turned on, under Get notifications for this Outpost.",
                        bundle: .module),
                    isSelected: choices.newPosts == .each
                ) { chooseNewPosts(.each) }

                ChoiceRow(
                    title: Text("None", bundle: .module),
                    detail: Text(
                        "Nothing when somebody posts, whatever any Outpost is set to.",
                        bundle: .module),
                    isSelected: choices.newPosts == .none
                ) { chooseNewPosts(.none) }
            } header: {
                Text("When somebody posts", bundle: .module).sectionHeading()
            } footer: {
                Text(
                    "Each Outpost has its own switch on its page. This is what happens across all of them.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                SettingsToggle(
                    icon: "bubble.left.and.text.bubble.right.fill",
                    title: Text("Comments on your posts", bundle: .module),
                    isOn: binding(.commentsOnMyPosts))
                SettingsToggle(
                    icon: "arrowshape.turn.up.left.fill",
                    title: Text("Posts you have commented on", bundle: .module),
                    isOn: binding(.repliesOnPostsICommentedOn))
                SettingsToggle(
                    icon: "hand.thumbsup.fill",
                    title: Text("Posts you have reacted to", bundle: .module),
                    isOn: binding(.repliesOnPostsIReactedTo))
            } header: {
                Text("When somebody comments", bundle: .module).sectionHeading()
            } footer: {
                Text(
                    "Writing a comment is what puts you in a thread. Reacting is kept separate — a reaction is not the same as joining in, so it is off until you ask for it.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                SettingsToggle(
                    icon: "heart.fill",
                    title: Text("Reactions to your posts", bundle: .module),
                    isOn: binding(.likesOnMyPosts))
            } header: {
                Text("When somebody reacts", bundle: .module).sectionHeading()
            } footer: {
                Text(
                    "Reactions arrive quietly: no sound, and they wait behind a Focus rather than breaking through it.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                SettingsToggle(
                    icon: "app.badge.fill",
                    title: Text("Show on the app icon", bundle: .module),
                    isOn: Binding(
                        get: { badges.outposts },
                        set: { on in
                            var updated = badges
                            updated.outposts = on
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
        .navigationTitle(Text("Outpost notifications", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
    }
}

public struct BadgeMeaningLine: View {
    private let meaning: BadgeChoices.Meaning

    public init(meaning: BadgeChoices.Meaning) {
        self.meaning = meaning
    }

    public var body: some View {
        switch meaning {
        case .both:
            Text(
                "The number on your app icon counts unread conversations and Outposts with something new.",
                bundle: .module)
        case .outpostsOnly:
            Text(
                "The number on your app icon counts Outposts with something new, and nothing else.",
                bundle: .module)
        case .messagesOnly:
            Text(
                "The number on your app icon counts unread conversations, and nothing else.",
                bundle: .module)
        case .off:
            Text("Your app icon shows no number at all.", bundle: .module)
        }
    }
}
