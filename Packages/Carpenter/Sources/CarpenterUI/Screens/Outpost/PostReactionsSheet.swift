import CarpenterKit
import SwiftUI

public struct PostReactionsSheet: View {
    @ScaledMetric(relativeTo: .title2) private var emoji: CGFloat = 28
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let reactions: [(emoji: String, count: Int)]
    private let mine: String?
    private let isReadOnly: Bool
    private let onReact: (String?) async -> Void

    public init(
        reactions: [(emoji: String, count: Int)],
        mine: String? = nil,
        isReadOnly: Bool = false,
        onReact: @escaping (String?) async -> Void = { _ in }
    ) {
        self.reactions = reactions
        self.mine = mine
        self.isReadOnly = isReadOnly
        self.onReact = onReact
    }

    private var total: Int { reactions.reduce(0) { $0 + $1.count } }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(reactions, id: \.emoji) { reaction in
                        row(reaction)
                    }
                } footer: {
                    if !isReadOnly {
                        Text(
                            "Tap one to react the same way, or tap your own to take it back. You have one reaction at a time.",
                            bundle: .module)
                    }
                }
                .groupedRowSurface()
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle(Text("^[\(total) reaction](inflect: true)", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
    }

    private func row(_ reaction: (emoji: String, count: Int)) -> some View {
        let isMine = reaction.emoji == mine
        return Button {
            guard !isReadOnly else { return }
            Task { await onReact(isMine ? nil : reaction.emoji) }
        } label: {
            HStack(spacing: 14) {
                Text(verbatim: reaction.emoji)
                    .font(.system(size: emoji))
                    .frame(width: emoji * 1.36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("^[\(reaction.count) person](inflect: true)", bundle: .module)
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)
                    if isMine {
                        Text("Including you", bundle: .module)
                            .font(CarpenterFont.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                if isMine {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.accentColor)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isReadOnly)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isMine ? [.isSelected] : [])
    }
}

#if DEBUG
    #Preview("Reactions on a post") {
        Color.clear.sizedSheet(isPresented: .constant(true)) {
            PostReactionsSheet(
                reactions: [
                    (emoji: "🔥", count: 9), (emoji: "😮", count: 6), (emoji: "👏", count: 4),
                    (emoji: "🎈", count: 2), (emoji: "❤️", count: 1),
                ],
                mine: "👏")
        }
        .themed(.default)
    }
#endif
