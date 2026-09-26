import CarpenterKit
import SwiftUI

struct PeoplePickerView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selected: Set<ParticipantID> = []

    let connections: [Connection]
    let onInvite: (Set<ParticipantID>) -> Void

    private var results: [Connection] { connections.matching(query) }
    private var sections: [(title: String, people: [Connection])] { results.sectionedByInitial() }

    var body: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.people) { connection in
                        row(connection)
                    }
                } header: {
                    Text(verbatim: section.title).sectionHeading()
                }
                .groupedRowSurface()
                .sectionIndexLabel(section.title)
            }
        }
        .scrollContentBackground(.hidden)
        #if os(iOS)
            .listSectionIndexVisibility(query.isEmpty ? .visible : .hidden)
        #endif
        .background(palette.background)
        // COPY BEGIN ec95494d [NEEDS HUMAN REVIEW]
        .searchable(text: $query, prompt: Text("Search people", bundle: .module))
        // COPY END ec95494d
        .autocorrectionDisabled()
        .overlay {
            if results.isEmpty { emptyState }
        }
        // COPY BEGIN 83539bd9 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Invite people", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    onInvite(selected)
                    dismiss()
                } label: {
                    Text("Invite", bundle: .module)
                }
                .disabled(selected.isEmpty)
            }
        }
        // COPY END 83539bd9
    }

    private func row(_ connection: Connection) -> some View {
        Button {
            if selected.contains(connection.id) {
                selected.remove(connection.id)
            } else {
                selected.insert(connection.id)
            }
        } label: {
            PersonRow(
                name: connection.person.displayName,
                initials: connection.person.initials,
                id: connection.person.id,
                detail: detail(for: connection)
            ) {
                Image(systemName: selected.contains(connection.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(
                        selected.contains(connection.id) ? palette.accentColor : palette.separator)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected.contains(connection.id) ? [.isSelected] : [])
    }

    // COPY BEGIN 76d88454 [NEEDS HUMAN REVIEW]
    private func detail(for connection: Connection) -> Text {
        if connection.sharedRooms > 0 {
            return Text("^[In \(connection.sharedRooms) room](inflect: true) with you", bundle: .module)
        }
        return Text("You can see their Outpost", bundle: .module)
    }
    // COPY END 76d88454

    private var emptyState: some View {
        // COPY BEGIN d477694b [NEEDS HUMAN REVIEW]
        ContentUnavailableView {
            Label {
                query.isEmpty
                    ? Text("Nobody to invite yet", bundle: .module)
                    : Text("Nobody by that name", bundle: .module)
            } icon: {
                Image(systemName: "person.2")
            }
        } description: {
            query.isEmpty
                ? Text("People you share a room with appear here.", bundle: .module)
                : Text("Try part of their name, or the code shown on their row.", bundle: .module)
        }
        .background(palette.background)
        // COPY END d477694b
    }
}

#if DEBUG
    #Preview("People picker") {
        NavigationStack {
            PeoplePickerView(
                connections: [
                    Connection(
                        person: Member(id: ParticipantID(rawValue: Data([1])), displayName: "Ada"),
                        sharedRooms: 2, seesTheirOutpost: true),
                    Connection(
                        person: Member(id: ParticipantID(rawValue: Data([2])), displayName: "Bo"),
                        sharedRooms: 0, seesTheirOutpost: true),
                    Connection(
                        person: Member(id: ParticipantID(rawValue: Data([3])), displayName: "C0C2"),
                        sharedRooms: 1, seesTheirOutpost: false),
                ],
                onInvite: { _ in }
            )
        }
        .themed(.default)
    }
#endif
