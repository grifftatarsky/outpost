import CarpenterKit
import SwiftUI

#if DEBUG

struct StyleTestView: View {
    @Environment(\.palette) private var palette

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ReactionOverflowStyleTest()
                } label: {
                    SettingsRow(
                        icon: "face.smiling", tone: .device,
                        title: Text("Reactions past the third", bundle: .module),
                        subtitle: Text(
                            "The top three and the stack that stands for the rest", bundle: .module))
                }
                NavigationLink {
                    TriangleStyleTest()
                } label: {
                    SettingsRow(
                        icon: "triangle", tone: .device,
                        title: Text("Three people, one Outpost", bundle: .module),
                        subtitle: Text(
                            "What each device draws when two readers have never met", bundle: .module))
                }
            } footer: {
                Text(
                    "These draw the real components with invented values. Nothing here is saved, sent, or read from your account.",
                    bundle: .module)
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(Text("Style test", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
    }
}

private struct ReactionOverflowStyleTest: View {
    @Environment(\.palette) private var palette

    private static let choices = ["🔥", "😮", "👏", "🎈", "❤️", "😂", "👍", "🙏", "✨", "💯"]

    @State private var front = "🎈"
    @State private var kinds = 5

    private var order: [String] {
        let rest = Self.choices.filter { $0 != front }
        return Array(rest.prefix(ReactionBar.shown)) + [front]
            + Array(rest.dropFirst(ReactionBar.shown))
    }

    private var reactions: [String: Set<ParticipantID>] {
        var made: [String: Set<ParticipantID>] = [:]
        let shown = order.prefix(max(0, kinds))
        for (index, emoji) in shown.enumerated() {
            let count = shown.count - index
            made[emoji] = Set(
                (0..<count).map { ParticipantID(rawValue: Data([UInt8(index), UInt8($0)])) })
        }
        return made
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    ReactionBar(
                        reactions: reactions, viewer: ParticipantID(rawValue: Data([9])),
                        commentCount: 4, onReact: { _ in }, isReadOnly: true)
                }
                .padding(.vertical, 6)
            } header: {
                Text("As a post draws it", bundle: .module).sectionHeading()
            } footer: {
                Text(
                    "Three at most, then one chip for the rest — tap it for a sheet with all of them, which is the only shape that holds nine. Growing the row ran off the edge with nowhere to scroll, and opening the keyboard answered a different question. The stack behind the chip is what says the list continues; a bare number would read as a count of people rather than of kinds. Nothing else on this row does anything: it is drawn read-only so no tap goes anywhere.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach([0, 1, 2, 3], id: \.self) { extra in
                        HStack(spacing: 10) {
                            Text("\(extra)", bundle: .module)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(palette.tertiaryText)
                                .frame(width: 18, alignment: .trailing)
                            if extra == 0 {
                                Text("nothing to hide", bundle: .module)
                                    .font(CarpenterFont.rowDetail)
                                    .foregroundStyle(palette.tertiaryText)
                            } else {
                                MoreReactionsChip(emoji: front, kinds: extra) {}
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("The chip on its own", bundle: .module).sectionHeading()
            } footer: {
                Text(
                    "One slice for one more kind, two for any number beyond that. The stack is a texture, not a fan.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                Stepper(value: $kinds, in: 0...Self.choices.count) {
                    Text("Different reactions: \(kinds)", bundle: .module)
                        .foregroundStyle(palette.primaryText)
                }
                Picker(selection: $front) {
                    ForEach(Self.choices, id: \.self) { emoji in
                        Text(verbatim: emoji).tag(emoji)
                    }
                } label: {
                    Text("Emoji on the chip", bundle: .module)
                }
                .pickerStyle(.menu)
                .tint(palette.accentColor)
            } header: {
                Text("Try it", bundle: .module).sectionHeading()
            } footer: {
                Text(
                    "The emoji you pick is made the fourth most reacted, so it is the one the chip carries. Below four, there is nothing to hide and no chip.",
                    bundle: .module)
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(Text("Reactions", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
    }
}

#endif
