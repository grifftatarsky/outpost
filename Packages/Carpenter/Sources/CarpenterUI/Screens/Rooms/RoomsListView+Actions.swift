import CarpenterKit
import SwiftUI

// MARK: What a row offers, and what the toolbar does

extension RoomsListView {
    @ViewBuilder
    func roomActions(for room: RoomSummary) -> some View {
        Button {
            organisation.setPinned(!organisation.isPinned(room.id), for: room.id, stamp: stamp())
        } label: {
            Label {
                organisation.isPinned(room.id)
                    ? Text("Unpin", bundle: .module) : Text("Pin", bundle: .module)
            } icon: {
                Image(systemName: organisation.isPinned(room.id) ? "pin.slash" : "pin")
            }
        }

        if room.hasUnread {
            Button {
                onMarkRead(room.id)
            } label: {
                Label {
                    Text("Mark as Read", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            }
        }

        Button {
            onSilence(room.id, !isSilenced(room.id))
        } label: {
            Label {
                isSilenced(room.id)
                    ? Text("Unsilence", bundle: .module) : Text("Silence", bundle: .module)
            } icon: {
                Image(systemName: isSilenced(room.id) ? "bell" : "moon")
            }
        }

        Button {
            taggingRoom = room
        } label: {
            Label {
                Text("Tags", bundle: .module)
            } icon: {
                Image(systemName: "tag")
            }
        }

        if let invited = visibleManagedTags.first(where: { $0.kind == .invited }) {
            Button {
                filter = filter == invited.id ? nil : invited.id
            } label: {
                Label {
                    filter == invited.id
                        ? Text("Show all rooms", bundle: .module)
                        : Text("Show only invited", bundle: .module)
                } icon: {
                    Image(systemName: "person.crop.circle.badge.clock")
                }
            }
        }

        if focus != nil {
            Divider()
            Button {
                isWritingFocusMessage = true
            } label: {
                Label {
                    Text("Do Not Disturb message", bundle: .module)
                } icon: {
                    Image(systemName: "moon.fill")
                }
            }
        }

        switch roomDeletion(room.id) {
        case .stillIn:
            if let onLeave {
                Divider()
                Button(role: .destructive) {
                    onLeave(room.id)
                } label: {
                    Label {
                        Text("Leave", bundle: .module)
                    } icon: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
                .tint(palette.destructive)
            }
        case .allowed:
            if let onDelete {
                Divider()
                Button(role: .destructive) {
                    onDelete(room.id)
                } label: {
                    Label {
                        Text("Delete", bundle: .module)
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
                .tint(palette.destructive)
            }
        case .departureNotSent:
            EmptyView()
        }
    }

    @ViewBuilder
    var composeButton: some View {
        switch scope {
        case .direct:
            Button { isStartingSolo = true } label: { composeGlyph }
                .accessibilityLabel(Text("New solo", bundle: .module))
        case .groups:
            Button { isNamingRoom = true } label: { composeGlyph }
                .accessibilityLabel(Text("New room", bundle: .module))
        case .everything:
            Menu {
                Button { isStartingSolo = true } label: {
                    Label {
                        Text("Solo", bundle: .module)
                    } icon: {
                        Image(systemName: "person")
                    }
                }
                Button { isNamingRoom = true } label: {
                    Label {
                        Text("Room", bundle: .module)
                    } icon: {
                        Image(systemName: "person.3")
                    }
                }
            } label: {
                composeGlyph
            }
            .accessibilityLabel(Text("New conversation", bundle: .module))
        }
    }

    private var composeGlyph: some View {
        Image(systemName: "square.and.pencil")
            .font(.system(size: 21, weight: .regular))
            .foregroundStyle(palette.primaryText)
    }

    var listMenu: some View {
        Menu {
            Section {
                Picker(
                    selection: Binding(
                        get: { preferences.density },
                        set: { preferences.density = $0 })
                ) {
                    Label {
                        Text("Comfortable", bundle: .module)
                    } icon: {
                        Image(systemName: "rectangle.grid.1x2")
                    }
                    .tag(RoomsListDensity.comfortable)
                    Label {
                        Text("Compact", bundle: .module)
                    } icon: {
                        Image(systemName: "rectangle.split.1x2")
                    }
                    .tag(RoomsListDensity.compact)
                } label: {
                    Text("Row size", bundle: .module)
                }
                .pickerStyle(.inline)
            }

            if let onJoinWithInvite {
                Button(action: onJoinWithInvite) {
                    Label {
                        Text("Join with an invite", bundle: .module)
                    } icon: {
                        Image(systemName: "qrcode")
                    }
                }
            }
            Button {
                isEditing = true
            } label: {
                Label {
                    Text("Edit list", bundle: .module)
                } icon: {
                    Image(systemName: "line.3.horizontal")
                }
            }
            Button {
                isManagingTags = true
            } label: {
                Label {
                    Text("Manage tags", bundle: .module)
                } icon: {
                    Image(systemName: "tag")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(palette.primaryText)
        }
        .accessibilityLabel(Text("Rooms list options", bundle: .module))
    }
}
