import CarpenterKit
import SwiftUI

public struct RoomTagsSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.clock) private var clock
    @Environment(\.stampDevice) private var stampDevice
    @Environment(\.dismiss) private var dismiss

    @Binding private var organisation: RoomsListOrganisation
    @State private var newTagName = ""

    private let room: RoomSummary

    public init(room: RoomSummary, organisation: Binding<RoomsListOrganisation>) {
        self.room = room
        _organisation = organisation
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(organisation.orderedTags) { tag in
                        Button {
                            let isOn = organisation.tags(of: room.id).contains(tag.id)
                            organisation.setTag(tag.id, on: !isOn, for: room.id, stamp: stamp())
                        } label: {
                            HStack {
                                Text(tag.name.value)
                                    .foregroundStyle(palette.primaryText)
                                Spacer()
                                if organisation.tags(of: room.id).contains(tag.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(palette.accentColor)
                                }
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        TextField(text: $newTagName) {
                            Text("New tag", bundle: .module)
                        }
                        .submitLabel(.next)
                        .onSubmit(createTag)

                        Button(action: createTag) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(trimmedNewTag.isEmpty)
                        .accessibilityLabel(Text("Add this tag", bundle: .module))
                    }
                }

                Section {
                } footer: {
                    Text(
                        "Tags live on your devices only. They are never sent in a packet, so no one else in the room can see how you have filed it.",
                        bundle: .module
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(room.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
        }
    }

    private var trimmedNewTag: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createTag() {
        guard !trimmedNewTag.isEmpty else { return }
        let tag = organisation.addTag(named: trimmedNewTag, stamp: stamp())
        organisation.setTag(tag, on: true, for: room.id, stamp: stamp())
        newTagName = ""
    }

    private func stamp() -> OrganisationStamp {
        OrganisationStamp(at: clock.now, device: stampDevice)
    }
}

public struct ManageTagsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.clock) private var clock
    @Environment(\.stampDevice) private var stampDevice
    @Environment(\.dismiss) private var dismiss

    @Binding private var organisation: RoomsListOrganisation
    @State private var newTagName = ""

    private let preferences: RoomsListPreferences

    public init(
        organisation: Binding<RoomsListOrganisation>,
        preferences: RoomsListPreferences
    ) {
        _organisation = organisation
        self.preferences = preferences
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(organisation.orderedTags) { tag in
                        HStack {
                            TagNameField(name: tag.name.value) { typed in
                                organisation.rename(tag.id, to: typed, stamp: stamp())
                            }
                            .foregroundStyle(palette.primaryText)

                            Spacer(minLength: 12)

                            Text(
                                organisation.roomCount(taggedWith: tag.id) == 1
                                    ? "1 room" : "\(organisation.roomCount(taggedWith: tag.id)) rooms",
                                bundle: .module
                            )
                            .foregroundStyle(palette.tertiaryText)
                        }
                    }
                    .onDelete { offsets in
                        for tag in offsets.map({ organisation.orderedTags[$0] }) {
                            organisation.removeTag(tag.id, stamp: stamp())
                        }
                    }
                    .onMove(perform: move)
                } header: {
                    Text(
                        "Your tags, on your devices. Order here is the order of the filter row on the rooms list.",
                        bundle: .module
                    )
                    .textCase(nil)
                }

                Section {
                    HStack {
                        TextField(text: $newTagName) {
                            Text("New tag", bundle: .module)
                        }
                        .submitLabel(.next)
                        .onSubmit(createTag)

                        Button(action: createTag) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(trimmedNewTag.isEmpty)
                        .accessibilityLabel(Text("Add this tag", bundle: .module))
                    }
                } footer: {
                    Text(
                        "Deleting a tag removes it from your rooms. It does not leave, mute or change any room.",
                        bundle: .module
                    )
                }

                Section {
                    Toggle(isOn: filterStyleBinding) {
                        Text("Filter from a menu", bundle: .module)
                    }
                } footer: {
                    Text(
                        "A row of chips is quicker to reach with a few tags. A menu takes the same two taps however many you have.",
                        bundle: .module
                    )
                }
            }
            .alwaysEditing()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text("Tags", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
        }
    }

    private var filterStyleBinding: Binding<Bool> {
        Binding(
            get: { preferences.tagFilterStyle == .menu },
            set: { preferences.tagFilterStyle = $0 ? .menu : .chips }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        var order = organisation.orderedTags
        order.move(fromOffsets: source, toOffset: destination)

        guard let moved = source.first.map({ organisation.orderedTags[$0] }),
            let landing = order.firstIndex(where: { $0.id == moved.id })
        else { return }

        organisation.moveTag(
            moved.id,
            between: landing > 0 ? order[landing - 1].id : nil,
            and: landing < order.count - 1 ? order[landing + 1].id : nil,
            stamp: stamp()
        )
    }

    private var trimmedNewTag: String {
        newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createTag() {
        guard !trimmedNewTag.isEmpty else { return }
        organisation.addTag(named: trimmedNewTag, stamp: stamp())
        newTagName = ""
    }

    private func stamp() -> OrganisationStamp {
        OrganisationStamp(at: clock.now, device: stampDevice)
    }
}

#if DEBUG
    private struct TagsPreview: View {
        @State private var organisation = Fixtures.organisation

        var body: some View {
            ManageTagsView(organisation: $organisation, preferences: RoomsListPreferences())
                .environment(\.clock, Fixtures.PreviewClock())
                .themed(.cobalt)
        }
    }

    #Preview("39 Manage tags — dark") {
        TagsPreview().preferredColorScheme(.dark)
    }

    #Preview("38 Room tags — dark") {
        RoomTagsSheetPreview().preferredColorScheme(.dark)
    }

    private struct RoomTagsSheetPreview: View {
        @State private var organisation = Fixtures.organisation

        var body: some View {
            RoomTagsSheet(room: Fixtures.rooms[0], organisation: $organisation)
                .environment(\.clock, Fixtures.PreviewClock())
                .themed(.cobalt)
        }
    }
#endif

private struct TagNameField: View {
    let name: String
    let onRename: (String) -> Void

    @State private var draft: String = ""
    @FocusState private var editing: Bool

    var body: some View {
        TextField(name, text: $draft)
            .focused($editing)
            .submitLabel(.done)
            .onSubmit(commit)
            .onAppear { draft = name }
            .onChange(of: name) { _, fresh in if !editing { draft = fresh } }
            .onChange(of: editing) { _, focused in if !focused { commit() } }
            .onDisappear(perform: commit)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draft = name
            return
        }
        guard trimmed != name else { return }
        onRename(trimmed)
    }
}
