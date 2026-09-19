import CarpenterKit
import SwiftUI

public struct ReactionBar: View {
    @ScaledMetric(relativeTo: .body) private var control: CGFloat = 30
    @Environment(\.palette) private var palette

    private let reactions: [String: Set<ParticipantID>]
    private let viewer: ParticipantID
    private let commentCount: Int?
    private let onReact: (String?) async -> Void
    private let thread: OutpostPost?
    private let isReadOnly: Bool

    @State private var isPickingEmoji = false
    @State private var isListingReactions = false

    public init(
        reactions: [String: Set<ParticipantID>],
        viewer: ParticipantID,
        commentCount: Int? = nil,
        onReact: @escaping (String?) async -> Void,
        thread: OutpostPost? = nil,
        isReadOnly: Bool = false
    ) {
        self.reactions = reactions
        self.viewer = viewer
        self.commentCount = commentCount
        self.onReact = onReact
        self.thread = thread
        self.isReadOnly = isReadOnly
    }

    private var ordered: [(emoji: String, members: Set<ParticipantID>)] {
        reactions
            .map { (emoji: $0.key, members: $0.value) }
            .sorted {
                $0.members.count != $1.members.count
                    ? $0.members.count > $1.members.count : $0.emoji < $1.emoji
            }
    }

    static let shown = 3

    private var visible: [(emoji: String, members: Set<ParticipantID>)] {
        Array(ordered.prefix(Self.shown))
    }
    private var hidden: [(emoji: String, members: Set<ParticipantID>)] {
        Array(ordered.dropFirst(Self.shown))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !ordered.isEmpty { marks }
            controls
        }
        .padding(.top, 2)
        .emojiPicker(isPresented: $isPickingEmoji) { emoji in
            isPickingEmoji = false
            Task { await onReact(emoji) }
        }
        .sizedSheet(isPresented: $isListingReactions) {
            PostReactionsSheet(
                reactions: ordered.map { (emoji: $0.emoji, count: $0.members.count) },
                mine: ordered.first { $0.members.contains(viewer) }?.emoji,
                isReadOnly: isReadOnly
            ) { emoji in
                isListingReactions = false
                await onReact(emoji)
            }
            .themed(.default)
        }
    }

    private var marks: some View {
        HStack(spacing: 7) {
            ForEach(visible, id: \.emoji) { reaction in
                let isMine = reaction.members.contains(viewer)

                Button {
                    guard !isReadOnly else { return }
                    Task { await onReact(isMine ? nil : reaction.emoji) }
                } label: {
                    HStack(spacing: 5) {
                        Text(reaction.emoji)
                            .font(.footnote)
                        Text(reaction.members.count, format: .number)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(isMine ? palette.accentColor : palette.neutralText)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background {
                        if isMine {
                            Capsule()
                                .fill(palette.accentTint)
                                .overlay { Capsule().strokeBorder(palette.accentColor, lineWidth: 1) }
                        } else {
                            Capsule().fill(palette.neutralFill)
                        }
                    }
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!isReadOnly)
                .tappable()
                .accessibilityLabel(
                    Text("\(reaction.emoji), \(reaction.members.count)", bundle: .module))
                .accessibilityAddTraits(isMine ? [.isSelected] : [])
            }

            if let next = hidden.first {
                MoreReactionsChip(emoji: next.emoji, kinds: hidden.count) {
                    isListingReactions = true
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint(Text("Shows every reaction", bundle: .module))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isListingReactions = true }
        .accessibilityActions {
            if !isReadOnly, ordered.contains(where: { $0.members.contains(viewer) }) {
                Button {
                    Task { await onReact(nil) }
                } label: {
                    Text("Remove my reaction", bundle: .module)
                }
            }
        }
    }

    var spoken: Text {
        ReactionSpeech.summary(
            ordered.map { (emoji: $0.emoji, count: $0.members.count, isMine: $0.members.contains(viewer)) })
    }

    private var controls: some View {
        HStack(spacing: 7) {
            if !isReadOnly {
            Button { isPickingEmoji = true } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: control * 0.57))
                    .foregroundStyle(palette.tertiaryText)
                    .frame(width: control, height: control)
                    .background {
                        Capsule().strokeBorder(
                            palette.fieldBorder, lineWidth: CarpenterMetrics.hairline)
                    }
            }
            .buttonStyle(.plain)
            .tappable()
            .accessibilityLabel(Text("Add a reaction", bundle: .module))
            }

            Spacer(minLength: 0)

            if let commentCount, let thread {
                NavigationLink(value: thread) {
                    Text(
                        commentCount == 1
                            ? "1 comment"
                            : (commentCount == 0 ? "Comment" : "\(commentCount) comments"),
                        bundle: .module
                    )
                    .font(CarpenterFont.postDetail)
                    .foregroundStyle(commentCount == 0 ? palette.accentColor : palette.tertiaryText)
                }
                .buttonStyle(.plain)
                .tappable()
            }
        }
    }
}

struct MoreReactionsChip: View {
    @Environment(\.palette) private var palette

    let emoji: String
    let kinds: Int
    let onOpen: () -> Void

    private static let slice: CGFloat = 5

    private var slices: Int { min(kinds, 2) }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 5) {
                Text(verbatim: emoji)
                    .font(.footnote)
                Text("more", bundle: .module)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.neutralText)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(alignment: .leading) {
                ZStack(alignment: .leading) {
                    ForEach(Array(stride(from: slices, to: 0, by: -1)), id: \.self) { depth in
                        Capsule()
                            .fill(palette.background)
                            .overlay { Capsule().fill(palette.neutralFill) }
                            .overlay {
                                Capsule().strokeBorder(
                                    palette.background, lineWidth: CarpenterMetrics.hairline * 2)
                            }
                            .offset(x: -Self.slice * CGFloat(depth))
                    }
                    Capsule()
                        .fill(palette.background)
                        .overlay { Capsule().fill(palette.neutralFill) }
                }
            }
            .padding(.leading, Self.slice * CGFloat(slices))
        }
        .buttonStyle(.plain)
        .tappable()
        .accessibilityLabel(
            Text("^[\(kinds) more reaction](inflect: true)", bundle: .module))
    }
}

struct EmojiPicker: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recents = RecentEmoji()
    @State private var query = ""

    let choose: (String) -> Void

    private let catalogue = EmojiCatalogue.shared

    @ScaledMetric(relativeTo: .body) private var scaledCell: CGFloat = 44

    private var cell: CGFloat { min(scaledCell, 88) }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cell), spacing: 6)]
    }

    private var found: [EmojiCatalogue.Entry] { catalogue.search(query) }

    var body: some View {
        VStack(spacing: 0) {
            field

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                    if query.isEmpty {
                        if !recents.emoji.isEmpty {
                            section(
                                Text("Recent", bundle: .module),
                                recents.emoji.map { EmojiCatalogue.Entry(emoji: $0, name: $0) })
                        }
                        ForEach(catalogue.groups) { group in
                            section(Text(verbatim: group.name), group.emoji)
                        }
                    } else if found.isEmpty {
                        Text("Nothing matches \(query).", bundle: .module)
                            .font(CarpenterFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 24)
                    } else {
                        section(
                            Text("^[\(found.count) match](inflect: true)", bundle: .module), found)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: query)
        }
        .frame(
            width: horizontalSizeClass == .regular ? 300 : nil,
            height: horizontalSizeClass == .regular ? 360 : nil)
        .background(palette.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.secondaryText)
            TextField(text: $query) {
                Text("Search by name", bundle: .module)
            }
            .submitLabel(.search)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            #if !os(macOS)
                .textInputAutocapitalization(.never)
            #endif
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear the search", bundle: .module))
            }
        }
        .font(CarpenterFont.rowDetail)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.fieldFill, in: .capsule)
        .padding(.horizontal, 14)
        .padding(.top, horizontalSizeClass == .regular ? 14 : 24)
        .padding(.bottom, 6)
    }

    private func section(_ title: Text, _ emoji: [EmojiCatalogue.Entry]) -> some View {
        Section {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(emoji) { entry in
                    button(entry)
                }
            }
        } header: {
            title
                .sectionHeading()
                .foregroundStyle(palette.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .background(palette.background)
        }
    }

    private func button(_ entry: EmojiCatalogue.Entry) -> some View {
        Button {
            recents.record(entry.emoji)
            choose(entry.emoji)
        } label: {
            Text(verbatim: entry.emoji)
                .font(.system(size: cell * 0.64))
                .frame(width: cell, height: cell)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: entry.name))
    }
}

private struct EmojiPickerPresentation: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var isPresented: Bool
    let choose: (String) -> Void

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content.popover(isPresented: $isPresented) { EmojiPicker(choose: choose) }
        } else {
            content.sizedSheet(isPresented: $isPresented) { EmojiPicker(choose: choose) }
        }
    }
}

private struct EmojiPickerItemPresentation<Item: Identifiable>: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var item: Item?
    let choose: (Item, String) -> Void

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content.popover(item: $item) { held in EmojiPicker { choose(held, $0) } }
        } else {
            content.sizedSheet(item: $item) { held in EmojiPicker { choose(held, $0) } }
        }
    }
}

extension View {
    func emojiPicker(isPresented: Binding<Bool>, choose: @escaping (String) -> Void) -> some View {
        modifier(EmojiPickerPresentation(isPresented: isPresented, choose: choose))
    }

    func emojiPicker<Item: Identifiable>(
        item: Binding<Item?>, choose: @escaping (Item, String) -> Void
    ) -> some View {
        modifier(EmojiPickerItemPresentation(item: item, choose: choose))
    }
}

@MainActor
@Observable
final class RecentEmoji {
    private static let key = "reactions.recent"
    private static let limit = 5

    private let defaults: UserDefaults

    private(set) var emoji: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        emoji = defaults.stringArray(forKey: Self.key) ?? []
    }

    func record(_ value: String) {
        emoji = ([value] + emoji.filter { $0 != value }).prefix(Self.limit).map { $0 }
        defaults.set(emoji, forKey: Self.key)
    }
}
