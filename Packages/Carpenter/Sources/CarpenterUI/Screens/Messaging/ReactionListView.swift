import CarpenterKit
import SwiftUI

public struct ReactionListView: View {
    @ScaledMetric(relativeTo: .title2) private var emoji: CGFloat = 26
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let message: Message
    private let member: (ParticipantID) -> Member?
    private let onToggle: (String?) async -> Void

    public init(
        message: Message,
        member: @escaping (ParticipantID) -> Member?,
        onToggle: @escaping (String?) async -> Void
    ) {
        self.message = message
        self.member = member
        self.onToggle = onToggle
    }

    private struct Row: Identifiable {
        let person: Member
        let emoji: String
        let isMine: Bool
        var id: String { "\(emoji)|\(person.id.shortCode)" }
    }

    private var rows: [Row] {
        var mine: [Row] = []
        var others: [Row] = []
        for (emoji, people) in message.reactions {
            for person in people {
                let named = member(person) ?? Member.placeholder(person)
                let row = Row(person: named, emoji: emoji, isMine: emoji == message.myReaction)
                if row.isMine, mine.isEmpty { mine.append(row) } else { others.append(row) }
            }
        }
        others.sort {
            $0.person.displayName != $1.person.displayName
                ? $0.person.displayName < $1.person.displayName : $0.emoji < $1.emoji
        }
        return mine + others.map { Row(person: $0.person, emoji: $0.emoji, isMine: false) }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { row in
                        Button {
                            Task { await onToggle(row.isMine ? nil : row.emoji) }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text(verbatim: row.emoji)
                                    .font(.system(size: emoji))
                                    .frame(width: emoji * 1.4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: row.person.displayName)
                                        .font(CarpenterFont.rowTitle)
                                        .foregroundStyle(palette.primaryText)
                                    (row.isMine
                                        ? Text("You · tap to remove", bundle: .module)
                                        : Text("Tap to react the same way", bundle: .module))
                                        .font(CarpenterFont.caption)
                                        .foregroundStyle(palette.secondaryText)
                                }
                                Spacer()
                            }
                        }
                        .accessibilityLabel(
                            row.isMine
                                ? Text("\(row.emoji), you. Removes your reaction.", bundle: .module)
                                : Text("\(row.emoji), \(row.person.displayName). Reacts the same way.", bundle: .module))
                    }
                } header: {
                    Text("^[\(rows.count) reaction](inflect: true)", bundle: .module).sectionHeading()
                }
                .groupedRowSurface()
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle(Text("Reactions", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
        }
    }
}

#if DEBUG
    #Preview("Who reacted") {
        ReactionListView(
            message: Message(
                id: MessageID(entry: EntryHash(rawValue: Data([1]))),
                author: Fixtures.hastur, body: "hello", sentAt: .now, isMine: false,
                reactions: ["❤️": [Fixtures.cassilda.id, Fixtures.yhtill.id], "👍": [Fixtures.camilla.id]],
                myReaction: "❤️"),
            member: { id in [Fixtures.cassilda, Fixtures.yhtill, Fixtures.camilla].first { $0.id == id } },
            onToggle: { _ in }
        )
        .themed(.default)
    }
#endif
