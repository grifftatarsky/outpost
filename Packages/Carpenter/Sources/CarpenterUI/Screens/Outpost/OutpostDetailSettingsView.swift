import CarpenterKit
import SwiftUI

public struct OutpostDetailSettingsView: View {
    @Environment(\.palette) private var palette

    private let person: Member
    private let isNotified: Bool
    private let acrossAllOutposts: NewPostNotifications
    private let onSetNotified: (Bool) async -> Void

    public init(
        person: Member, isNotified: Bool, acrossAllOutposts: NewPostNotifications,
        onSetNotified: @escaping (Bool) async -> Void
    ) {
        self.person = person
        self.isNotified = isNotified
        self.acrossAllOutposts = acrossAllOutposts
        self.onSetNotified = onSetNotified
    }

    public var body: some View {
        List {
            Section {
                SettingsToggle(
                    icon: "bell.fill",
                    title: Text("Get notifications for this Outpost", bundle: .module),
                    isOn: Binding(
                        get: { isNotified },
                        set: { on in Task { await onSetNotified(on) } }))
            } footer: {
                switch acrossAllOutposts {
                case .each:
                    Text(
                        "\(person.displayName) is not told that you asked, and nobody is. This is a setting on your phone.",
                        bundle: .module)
                case .all:
                    Text(
                        "Under Notifications you have chosen to be told about **all posts**, so you are told about this Outpost whatever this switch says. Your answer here is kept for when you change that.",
                        bundle: .module)
                case .none:
                    Text(
                        "Under Notifications you have chosen to be told about **no posts**, so you are told about none of them whatever this switch says. Your answer here is kept for when you change that.",
                        bundle: .module)
                }
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(Text(verbatim: person.displayName))
        .toolbarTitleDisplayMode(.inline)
    }
}

public struct OutpostDetailSettings {
    public let person: Member
    public let isNotified: Bool
    public let acrossAllOutposts: NewPostNotifications
    public let onSetNotified: (Bool) async -> Void

    public init(
        person: Member, isNotified: Bool, acrossAllOutposts: NewPostNotifications,
        onSetNotified: @escaping (Bool) async -> Void
    ) {
        self.person = person
        self.isNotified = isNotified
        self.acrossAllOutposts = acrossAllOutposts
        self.onSetNotified = onSetNotified
    }
}
