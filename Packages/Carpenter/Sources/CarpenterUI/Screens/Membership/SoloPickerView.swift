import CarpenterKit
import SwiftUI

struct SoloPickerView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    let connections: [Connection]
    let onPick: (Member) async -> Void

    private var results: [Connection] { connections.matching(query) }
    private var sections: [(title: String, people: [Connection])] { results.sectionedByInitial() }

    var body: some View {
        NavigationStack {
            Group {
                if connections.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("Nobody to send to yet", bundle: .module)
                        } icon: {
                            Image(systemName: "person")
                        }
                    } description: {
                        Text(
                            "A solo is with somebody you already share a room with. Once you do, they appear here.",
                            bundle: .module)
                    }
                    .background(palette.background)
                } else {
                    List {
                        ForEach(sections, id: \.title) { section in
                            Section {
                                ForEach(section.people) { connection in
                                    Button {
                                        dismiss()
                                        Task { await onPick(connection.person) }
                                    } label: {
                                        HStack(spacing: 12) {
                                            PersonAvatarView(member: connection.person, diameter: 36)
                                            Text(connection.person.displayName)
                                                .foregroundStyle(palette.primaryText)
                                        }
                                    }
                                }
                            } header: {
                                Text(verbatim: section.title).sectionHeading()
                            }
                            .groupedRowSurface()
                            .sectionIndexLabel(section.title)
                        }
                    }
                    .searchable(text: $query, prompt: Text("Search people", bundle: .module))
                    .autocorrectionDisabled()
                    .overlay {
                        if sections.isEmpty, !query.isEmpty {
                            ContentUnavailableView {
                                Label {
                                    Text("Nobody by that name", bundle: .module)
                                } icon: {
                                    Image(systemName: "person.2")
                                }
                            } description: {
                                Text(
                                    "Try part of their name, or the code shown on their row.",
                                    bundle: .module)
                            }
                            .background(palette.background)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(palette.background)
                }
            }
            .navigationTitle(Text("New solo", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }
}
