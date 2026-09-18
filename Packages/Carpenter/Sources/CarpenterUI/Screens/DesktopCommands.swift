import CarpenterKit
import SwiftUI

// MARK: The Mac's menu bar, driven by the window in front

struct DesktopActions {
    struct Area {
        let area: WideArea
        let title: LocalizedStringResource
    }

    struct OpenRoom {
        let name: String
        let hasUnread: Bool
        let isPinned: Bool
        let isSilenced: Bool
        let deletion: RoomDeletion
        let markRead: () -> Void
        let setPinned: (Bool) -> Void
        let setSilenced: (Bool) -> Void
        let leave: () -> Void
        let delete: () -> Void
    }

    let newRoom: () -> Void
    let newSolo: () -> Void
    let joinWithInvite: (() -> Void)?
    let audienceShown: Bool?
    let toggleAudience: () -> Void
    let areas: [Area]
    let current: WideArea
    let show: (WideArea) -> Void
    let rooms: [(id: RoomID, name: String)]
    let openRoom: OpenRoom?
    let go: (RootView.Destination) -> Void

    static let placeholderAreas: [LocalizedStringResource] = [
        .module("Messages"), .module("Outposts"), .module("Search"), .module("You"),
    ]
}

extension FocusedValues {
    @Entry var desktopActions: DesktopActions?
}

public struct DesktopCommands: Commands {
    @FocusedValue(\.desktopActions) private var actions
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    public static let howItWorksWindow = "how-it-works"

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button { actions?.newRoom() } label: {
                Text("New Room…", bundle: .module)
            }
            .keyboardShortcut("n")
            .disabled(actions == nil)
            Button { actions?.newSolo() } label: {
                Text("New Solo…", bundle: .module)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(actions == nil)
            Button { actions?.joinWithInvite?() } label: {
                Text("Join with an Invite…", bundle: .module)
            }
            .disabled(actions?.joinWithInvite == nil)
        }

        #if os(macOS)
            CommandGroup(after: .textEditing) {
                Button { actions?.show(.search) } label: {
                    Text("Search", bundle: .module)
                }
                .keyboardShortcut("f")
                .disabled(actions == nil)
            }
        #endif

        SidebarCommands()

        CommandGroup(after: .sidebar) {
            Button { actions?.toggleAudience() } label: {
                if actions?.audienceShown == true {
                    Text("Hide Who Sees Your Outpost", bundle: .module)
                } else {
                    Text("Show Who Sees Your Outpost", bundle: .module)
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(actions?.audienceShown == nil)
        }

        CommandMenu(Text("Go", bundle: .module)) {
            ForEach(Array((actions?.areas ?? []).enumerated()), id: \.offset) { index, area in
                Toggle(
                    isOn: Binding(
                        get: { actions?.current == area.area },
                        set: { _ in actions?.show(area.area) })
                ) {
                    Text(area.title)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
            if actions == nil {
                ForEach(Array(DesktopActions.placeholderAreas.enumerated()), id: \.offset) { _, title in
                    Button {} label: { Text(title) }  // intentionally empty
                        .disabled(true)
                }
            }
            if let rooms = actions?.rooms, !rooms.isEmpty {
                Divider()
                Menu {
                    ForEach(rooms.prefix(30), id: \.id) { room in
                        Button { actions?.go(.room(room.id)) } label: {
                            Text(verbatim: room.name)
                        }
                    }
                } label: {
                    Text("Conversations", bundle: .module)
                }
            }
        }

        CommandMenu(Text("Conversation", bundle: .module)) {
            let room = actions?.openRoom
            Button { room?.markRead() } label: {
                Text("Mark as Read", bundle: .module)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(room?.hasUnread != true)
            Button { room?.setPinned(!(room?.isPinned ?? false)) } label: {
                if room?.isPinned == true {
                    Text("Unpin", bundle: .module)
                } else {
                    Text("Pin", bundle: .module)
                }
            }
            .disabled(room == nil)
            Button { room?.setSilenced(!(room?.isSilenced ?? false)) } label: {
                if room?.isSilenced == true {
                    Text("Unsilence", bundle: .module)
                } else {
                    Text("Silence", bundle: .module)
                }
            }
            .disabled(room == nil)
            Divider()
            Button { room?.leave() } label: {
                Text("Leave…", bundle: .module)
            }
            .disabled(room?.deletion != .stillIn)
            Button { room?.delete() } label: {
                Text("Delete…", bundle: .module)
            }
            .disabled(room?.deletion != .allowed)
        }

        #if os(macOS)
            CommandGroup(replacing: .help) {
                Button { openWindow(id: Self.howItWorksWindow) } label: {
                    Text("How This Works", bundle: .module)
                }
            }
        #endif
    }
}
