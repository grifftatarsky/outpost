import CarpenterKit
import SwiftUI

// MARK: The Mac's menu bar, driven by the window in front

struct DesktopActions {
    let newRoom: () -> Void
    let newSolo: () -> Void
    let joinWithInvite: (() -> Void)?
    let audienceShown: Bool?
    let toggleAudience: () -> Void
    let rooms: [(id: RoomID, name: String)]
    let owner: ParticipantID
    let go: (RootView.Destination) -> Void
}

extension FocusedValues {
    @Entry var desktopActions: DesktopActions?
}

#if os(macOS)
    public struct DesktopCommands: Commands {
        @FocusedValue(\.desktopActions) private var actions
        @Environment(\.openWindow) private var openWindow

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
                Button { actions?.go(.allOutposts) } label: {
                    Text("All Outposts", bundle: .module)
                }
                .disabled(actions == nil)
                Button {
                    if let actions { actions.go(.outpost(actions.owner)) }
                } label: {
                    Text("Your Outpost", bundle: .module)
                }
                .disabled(actions == nil)
                Button { actions?.go(.you) } label: {
                    Text("You", bundle: .module)
                }
                .disabled(actions == nil)
                if let rooms = actions?.rooms, !rooms.isEmpty {
                    Divider()
                    ForEach(Array(rooms.prefix(9).enumerated()), id: \.offset) { index, room in
                        Button { actions?.go(.room(room.id)) } label: {
                            Text(verbatim: room.name)
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    }
                }
            }

            CommandGroup(replacing: .help) {
                Button { openWindow(id: Self.howItWorksWindow) } label: {
                    Text("How This Works", bundle: .module)
                }
            }
        }
    }
#endif
