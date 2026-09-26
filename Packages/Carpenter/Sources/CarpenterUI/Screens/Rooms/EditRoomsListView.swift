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

    private let isSilenced: (RoomID) -> Bool
    private let onSilence: (RoomID, Bool) -> Void
    private let onLeave: ((RoomID) -> Void)?
    private let roomDeletion: (RoomID) -> RoomDeletion
    private let onDelete: ((RoomID) -> Void)?

    // COPY BEGIN e13f99f6 [NEEDS HUMAN REVIEW]
    public init(
        rooms: [RoomSummary],
        title: LocalizedStringResource = .module("Rooms"),
        organisation: Binding<RoomsListOrganisation>,
        isSilenced: @escaping (RoomID) -> Bool = { _ in false },
        onSilence: @escaping (RoomID, Bool) -> Void = { _, _ in },
        onLeave: ((RoomID) -> Void)? = nil,
        roomDeletion: @escaping (RoomID) -> RoomDeletion = { _ in .stillIn },
        onDelete: ((RoomID) -> Void)? = nil
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
    // COPY END e13f99f6

    private var pinned: [RoomSummary] {
        organisation.arrange(rooms).filter { organisation.isPinned($0.id) }
    }

    private var unpinned: [RoomSummary] {
        organisation.arrange(rooms).filter { !organisation.isPinned($0.id) }
    }

    public var body: some View {
        NavigationStack {
            List {
                // COPY BEGIN 4d7f8c96 [NEEDS HUMAN REVIEW]
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
                // COPY END 4d7f8c96

                Section {
                    ForEach(unpinned) { room in
                        row(room)
                            .swipeActions(edge: .trailing) {
                                switch roomDeletion(room.id) {
                                case .stillIn:
                                    // COPY BEGIN 1b7300b7 [NEEDS HUMAN REVIEW]
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
                                    // COPY END 1b7300b7
                                case .departureNotSent:
                                    EmptyView()
                                }
                            }
                    }
                } header: {
                    // COPY BEGIN 89fbaece [NEEDS HUMAN REVIEW]
                    Text("Most recent", bundle: .module)
                    // COPY END 89fbaece
                }
            }
            .alwaysEditing()
            .navigationTitle(Text(title))
            // COPY BEGIN 7ce6b199 [NEEDS HUMAN REVIEW]
            .safeAreaInset(edge: .top) {
                Text(
                    "Drag to reorder your pins. Tap a room's tags to change them. Swipe to leave.",
                    bundle: .module
                )
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
            // COPY END 7ce6b199
            .sheet(item: $taggingRoom) { room in
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
                // COPY BEGIN 3ec7fe0b [NEEDS HUMAN REVIEW]
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
                // COPY END 3ec7fe0b

                Button {
                    taggingRoom = room
                } label: {
                    // COPY BEGIN 95fa5195 [NEEDS HUMAN REVIEW]
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
                    // COPY END 95fa5195
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        // COPY BEGIN 6cb57963 [NEEDS HUMAN REVIEW]
        .swipeActions(edge: .leading) {
            Button {
                onSilence(room.id, !isSilenced(room.id))
            } label: {
                isSilenced(room.id)
                    ? Text("Unsilence", bundle: .module) : Text("Silence", bundle: .module)
            }
        }
        // COPY END 6cb57963
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
        // COPY BEGIN 24d51251 [NEEDS HUMAN REVIEW]
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
        // COPY END 24d51251
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
