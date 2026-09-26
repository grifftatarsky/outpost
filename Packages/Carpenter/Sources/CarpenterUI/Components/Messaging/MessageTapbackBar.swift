import CarpenterKit
import SwiftUI

public struct MessageTapbackBar<Actions: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let favourites: [String]
    private let chosen: String?
    private let onPick: (String?) async -> Void
    private let onMoreEmoji: () -> Void
    private let actions: () -> Actions

    public init(
        favourites: [String],
        chosen: String?,
        onPick: @escaping (String?) async -> Void,
        onMoreEmoji: @escaping () -> Void,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.favourites = favourites
        self.chosen = chosen
        self.onPick = onPick
        self.onMoreEmoji = onMoreEmoji
        self.actions = actions
    }

    public var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(favourites, id: \.self) { emoji in
                    tapback(emoji)
                }

                more
                overflow
            }
        }
        .padding(6)
    }

    private func tapback(_ emoji: String) -> some View {
        let isChosen = emoji == chosen
        return Button {
            Task { await onPick(isChosen ? nil : emoji) }
        } label: {
            Text(verbatim: emoji)
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background {
                    if isChosen { Circle().fill(palette.accentTint) }
                }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isChosen)
        .accessibilityLabel(Text(verbatim: emoji))
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    // COPY BEGIN de3759aa [NEEDS HUMAN REVIEW]
    private var more: some View {
        Button(action: onMoreEmoji) {
            Image(systemName: "face.smiling")
                .font(.system(size: 18))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(Text("More reactions", bundle: .module))
    }
    // COPY END de3759aa

    // COPY BEGIN d8781b79 [NEEDS HUMAN REVIEW]
    private var overflow: some View {
        Menu {
            actions()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 44, height: 44)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(Text("More actions", bundle: .module))
    }
    // COPY END d8781b79
}

public struct MessageReactions: View {
    @Environment(\.palette) private var palette

    public static let diameter: CGFloat = 34
    private static let emojiSize: CGFloat = 19
    private static let overlap: CGFloat = 8
    private static let visible = 3

    private let reactions: [String: Set<ParticipantID>]
    private let mine: String?
    private let onToggle: (String?) async -> Void
    private let onOpen: () -> Void

    public init(
        reactions: [String: Set<ParticipantID>],
        mine: String?,
        onToggle: @escaping (String?) async -> Void,
        onOpen: @escaping () -> Void = {}
    ) {
        self.reactions = reactions
        self.mine = mine
        self.onToggle = onToggle
        self.onOpen = onOpen
    }

    private struct Reaction: Identifiable {
        let emoji: String
        let isMine: Bool
        let id: String
    }

    private var ordered: [Reaction] {
        var own: [Reaction] = []
        var others: [Reaction] = []
        for (emoji, people) in reactions {
            for person in people {
                let hex = person.rawValue.map { String(format: "%02x", $0) }.joined()
                let reaction = Reaction(emoji: emoji, isMine: emoji == mine, id: "\(emoji)|\(hex)")
                if emoji == mine, own.isEmpty { own.append(reaction) } else { others.append(reaction) }
            }
        }
        others.sort { $0.emoji != $1.emoji ? $0.emoji < $1.emoji : $0.id < $1.id }
        return own + others.map { Reaction(emoji: $0.emoji, isMine: false, id: $0.id) }
    }

    public var body: some View {
        let ordered = ordered
        let shown = Array(ordered.prefix(Self.visible))
        let hidden = ordered.count - shown.count

        HStack(spacing: -Self.overlap) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, reaction in
                Button(action: onOpen) {
                    circle(Text(verbatim: reaction.emoji).font(.system(size: Self.emojiSize)), isMine: reaction.isMine)
                }
                .buttonStyle(.plain)
                .zIndex(Double(shown.count - index))
            }
            if hidden > 0 {
                Button(action: onOpen) {
                    circle(
                        Text(verbatim: "+\(hidden)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.primaryText),
                        isMine: false)
                }
                .buttonStyle(.plain)
                .zIndex(0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        // COPY BEGIN a2a846aa [NEEDS HUMAN REVIEW]
        .accessibilityHint(Text("Double-tap to see who reacted", bundle: .module))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .accessibilityAction(named: Text("Remove my reaction", bundle: .module)) {
            guard mine != nil else { return }
            Task { await onToggle(nil) }
        }
        // COPY END a2a846aa
    }

    private func circle(_ content: Text, isMine: Bool) -> some View {
        content
            .frame(width: Self.diameter, height: Self.diameter)
            .background {
                ZStack {
                    Circle().fill(palette.background)
                    Circle().fill(isMine ? palette.sentBubbleFill : palette.neutralFillStrong)
                }
            }
    }

    private var summary: Text {
        ReactionSpeech.summary(
            reactions.map { (emoji: $0.key, count: $0.value.count, isMine: $0.key == mine) })
    }
}

enum ReactionSpeech {
    static func summary(_ reactions: [(emoji: String, count: Int, isMine: Bool)]) -> Text {
        let counted = reactions.sorted { $0.isMine != $1.isMine ? $0.isMine : $0.emoji < $1.emoji }
        var parts: [Text] = []
        // COPY BEGIN 8e885bcd [NEEDS HUMAN REVIEW]
        for reaction in counted {
            let others = reaction.count - (reaction.isMine ? 1 : 0)
            let who: Text
            switch (reaction.isMine, others) {
            case (true, 0): who = Text("from you", bundle: .module)
            case (true, _): who = Text("from you and ^[\(others) other](inflect: true)", bundle: .module)
            case (false, _): who = Text("from ^[\(others) person](inflect: true)", bundle: .module)
            }
            parts.append(Text("\(reaction.emoji) \(who)", bundle: .module))
        }
        let list = parts.dropFirst().reduce(parts.first ?? Text(verbatim: "")) {
            Text("\($0), \($1)", bundle: .module)
        }
        return Text("Reactions: \(list)", bundle: .module)
        // COPY END 8e885bcd
    }
}

#if DEBUG
    #Preview("The tapback bar") {
        MessageTapbackBar(
            favourites: FavouriteEmoji.starting,
            chosen: "👍",
            onPick: { _ in },
            onMoreEmoji: {}
        ) {
            Button("Details") {}
        }
        .padding(40)
        .themed(.default)
        .preferredColorScheme(.dark)
    }
#endif
