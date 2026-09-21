import CarpenterKit
import SwiftUI

public struct EditRoomsListView: View {
    @Environment(\.palette) private var palette
    @Environment(\.clock) private var clock
    @Environment(\.stampDevice) private var stampDevice
    @Environment(\.dismiss) private var dismiss

    @Binding private var organisation: RoomsListOrganisation
    @State private var taggingRoom: RoomSummary?

    private let rooms: [RoomSummary]
    private let title: LocalizedStringResource

    private let isSilenced: (ConversationID) -> Bool
    private let onSilence: (ConversationID, Bool) -> Void
    private let onLeave: ((ConversationID) -> Void)?
    private let roomDeletion: (ConversationID) -> RoomDeletion
    private let onDelete: ((ConversationID) -> Void)?

    public init(
        rooms: [RoomSummary],
        title: LocalizedStringResource = .module("Rooms"),
        organisation: Binding<RoomsListOrganisation>,
        isSilenced: @escaping (ConversationID) -> Bool = { _ in false },
        onSilence: @escaping (ConversationID, Bool) -> Void = { _, _ in },
        onLeave: ((ConversationID) -> Void)? = nil,
        roomDeletion: @escaping (ConversationID) -> RoomDeletion = { _ in .stillIn },
        onDelete: ((ConversationID) -> Void)? = nil
    ) {
        self.roomDeletion = roomDeletion
        self.onDelete = onDelete
        self.rooms = rooms
        self.title = title
        _organisation = organisation
        self.isSilenced = isSilenced
        self.onLeave = onLeave
        self.onSilence = onSilence
    }

    private var pinned: [RoomSummary] {
        organisation.arrange(rooms).filter { organisation.isPinned($0.id) }
    }

    private var unpinned: [RoomSummary] {
        organisation.arrange(rooms).filter { !organisation.isPinned($0.id) }
    }

    public var body: some View {
        NavigationStack {
            List {
                if !pinned.isEmpty {
                    Section {
                        ForEach(pinned) { room in
                            row(room)
                        }
                        .onMove(perform: movePins)
                    } header: {
                        Text("Pinned", bundle: .module)
                    }
                }

                Section {
                    ForEach(unpinned) { room in
                        row(room)
                            .swipeActions(edge: .trailing) {
                                departure(room)
                            }
                    }
                } header: {
                    Text("Most recent", bundle: .module)
                }
            }
            .alwaysEditing()
            .navigationTitle(Text(title))
            .safeAreaInset(edge: .top) {
                (Platform.isMac
                    ? Text(
                        "Drag to reorder your pins. Click a room's tags to change them. Control-click a room to leave it.",
                        bundle: .module)
                    : Text(
                        "Drag to reorder your pins. Tap a room's tags to change them. Swipe to leave.",
                        bundle: .module))
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CarpenterMetrics.screenMargin)
                .padding(.bottom, 6)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
            .sizedSheet(item: $taggingRoom) { room in
                RoomTagsSheet(room: room, organisation: $organisation)
            }
        }
    }

    private func row(_ room: RoomSummary) -> some View {
        HStack(spacing: 12) {
            Button {
                organisation.setPinned(!organisation.isPinned(room.id), for: room.id, stamp: stamp())
            } label: {
                PinToggle(isOn: organisation.isPinned(room.id))
            }
            .buttonStyle(.plain)

            AvatarView(
                initials: room.initials, diameter: CarpenterMetrics.composerAvatar,
                isAccented: organisation.isPinned(room.id))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(room.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    if isSilenced(room.id) {
                        Image(systemName: "moon.fill")
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryText)
                            .accessibilityLabel(Text("Silenced", bundle: .module))
                    }
                }

                Button {
                    taggingRoom = room
                } label: {
                    HStack(spacing: 5) {
                        let assigned = organisation.orderedTags
                            .filter { organisation.tags(of: room.id).contains($0.id) }
                        ForEach(assigned) { tag in
                            TagChip(title: tag.name.value)
                        }
                        if assigned.isEmpty {
                            TagChip(title: "+ Tag", isPlaceholder: true)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .swipeActions(edge: .leading) {
            silence(room)
        }
        .contextMenu {
            silence(room)
            if !pinned.contains(where: { $0.id == room.id }) {
                departure(room)
            }
        }
    }

    private func silence(_ room: RoomSummary) -> some View {
        Button {
            onSilence(room.id, !isSilenced(room.id))
        } label: {
            isSilenced(room.id)
                ? Text("Unsilence", bundle: .module) : Text("Silence", bundle: .module)
        }
    }

    @ViewBuilder
    private func departure(_ room: RoomSummary) -> some View {
        switch roomDeletion(room.id) {
        case .stillIn:
            if let onLeave {
                Button(role: .destructive) {
                    onLeave(room.id)
                } label: {
                    Text("Leave", bundle: .module)
                }
            }
        case .allowed:
            if let onDelete {
                Button(role: .destructive) {
                    onDelete(room.id)
                } label: {
                    Text("Delete", bundle: .module)
                }
            }
        case .departureNotSent:
            EmptyView()
        }
    }

    private func movePins(from source: IndexSet, to destination: Int) {
        var order = pinned
        order.move(fromOffsets: source, toOffset: destination)

        guard let moved = source.first.map({ pinned[$0] }),
            let landing = order.firstIndex(where: { $0.id == moved.id })
        else { return }

        organisation.movePin(
            moved.id,
            between: landing > 0 ? order[landing - 1].id : nil,
            and: landing < order.count - 1 ? order[landing + 1].id : nil,
            stamp: stamp()
        )
    }

    private func stamp() -> OrganisationStamp {
        OrganisationStamp(at: clock.now, device: stampDevice)
    }
}

private struct PinToggle: View {
    @Environment(\.palette) private var palette

    let isOn: Bool

    var body: some View {
        Circle()
            .fill(isOn ? palette.accentColor : .clear)
            .frame(width: 26, height: 26)
            .overlay {
                if !isOn {
                    Circle().strokeBorder(palette.tertiaryText, lineWidth: 1.5)
                }
            }
            .overlay {
                Image(systemName: "pin.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isOn ? palette.textOnAccent : palette.tertiaryText)
            }
            .accessibilityLabel(Text(isOn ? "Unpin" : "Pin", bundle: .module))
    }
}

#if DEBUG
    private struct EditPreview: View {
        @State private var organisation = Fixtures.organisation

        var body: some View {
            EditRoomsListView(rooms: Fixtures.rooms, organisation: $organisation)
                .environment(\.clock, Fixtures.PreviewClock())
                .themed(.cobalt)
        }
    }

    #Preview("37 Edit list — dark") {
        EditPreview().preferredColorScheme(.dark)
    }
#endif
