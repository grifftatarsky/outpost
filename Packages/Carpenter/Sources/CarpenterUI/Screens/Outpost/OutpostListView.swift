import CarpenterKit
import SwiftUI

public struct AllOutpostsRoute: Hashable, Sendable {
    public init() {}
}

public struct OutpostListView: View {
    @Environment(\.palette) private var palette

    private let people: [Member]
    private let unseen: Set<ParticipantID>
    private let notified: Set<ParticipantID>
    private let onMarkSeen: (ParticipantID) async -> Void
    private let onSetNotified: (ParticipantID, Bool) async -> Void

    @State private var query = ""

    public init(
        people: [Member],
        unseen: Set<ParticipantID> = [],
        notified: Set<ParticipantID> = [],
        onMarkSeen: @escaping (ParticipantID) async -> Void = { _ in },
        onSetNotified: @escaping (ParticipantID, Bool) async -> Void = { _, _ in }
    ) {
        self.people = people
        self.unseen = unseen
        self.notified = notified
        self.onMarkSeen = onMarkSeen
        self.onSetNotified = onSetNotified
    }

    private var shown: [Member] {
        people
            .filter { query.isEmpty || $0.displayName.localizedStandardContains(query) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var sections: [(letter: String, people: [Member])] {
        var found: [(String, [Member])] = []
        for person in shown {
            let letter = Self.index(of: person.displayName)
            if let last = found.indices.last, found[last].0 == letter {
                found[last].1.append(person)
            } else {
                found.append((letter, [person]))
            }
        }
        return found.map { (letter: $0.0, people: $0.1) }
    }

    static func index(of name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespaces).first else { return "#" }
        let upper = String(first).uppercased()
        return first.isLetter ? upper : "#"
    }

    public var body: some View {
        List {
            ForEach(sections, id: \.letter) { section in
                Section {
                    ForEach(section.people) { person in
                        row(person)
                    }
                } header: {
                    Text(verbatim: section.letter).sectionHeading()
                }
                .groupedRowSurface()
            }
        }
        #if os(iOS)
            .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(palette.background)
        #if os(iOS)
            .listSectionIndexVisibility(query.isEmpty ? .visible : .hidden)
        #endif
        .searchable(text: $query, prompt: Text("Search people", bundle: .module))
        .tint(palette.accentColor)
        .navigationTitle(Text("All Outposts", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        .overlay {
            if shown.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("Nobody's Outpost yet", bundle: .module)
                        } icon: {
                            Image(systemName: "person.2")
                        }
                    } description: {
                        Text(
                            "Somebody who lets you read their Outpost appears here.",
                            bundle: .module)
                    }
                    .background(palette.background)
                } else {
                    ContentUnavailableView.search(text: query)
                        .background(palette.background)
                }
            }
        }
    }

    private func row(_ person: Member) -> some View {
        NavigationLink(value: person.id) {
            PersonRow(
                name: person.displayName, initials: person.initials, id: person.id,
                detail: detail(for: person)
            ) {
                if notified.contains(person.id) {
                    Image(systemName: "bell.fill")
                        .font(.footnote)
                        .foregroundStyle(palette.accentColor)
                        .accessibilityLabel(Text("You are told about their posts", bundle: .module))
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                Task { await onSetNotified(person.id, !notified.contains(person.id)) }
            } label: {
                Label {
                    notified.contains(person.id)
                        ? Text("Stop telling me", bundle: .module)
                        : Text("Tell me", bundle: .module)
                } icon: {
                    Image(systemName: notified.contains(person.id) ? "bell.slash" : "bell")
                }
            }
            .tint(palette.accentColor)
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await onMarkSeen(person.id) }
            } label: {
                Label {
                    Text("Mark read", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            }
            .tint(palette.accentColor)
            .disabled(!unseen.contains(person.id))
        }
    }

    private func detail(for person: Member) -> Text {
        unseen.contains(person.id)
            ? Text("Something new", bundle: .module)
            : Text("Up to date", bundle: .module)
    }
}

#if DEBUG
    #Preview("All Outposts") {
        NavigationStack {
            OutpostListView(
                people: [Fixtures.camilla, Fixtures.hastur, Fixtures.cassilda],
                unseen: [Fixtures.hastur.id],
                notified: [Fixtures.camilla.id])
        }
        .themed(.default)
    }
#endif
