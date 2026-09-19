import CarpenterKit
import SwiftUI

public struct MessageBubbleView: View {
    @Environment(\.palette) private var palette

    private let text: String
    private let isMine: Bool
    private let position: BubblePosition

    public init(text: String, isMine: Bool, position: BubblePosition) {
        self.text = text
        self.isMine = isMine
        self.position = position
    }

    public var body: some View {
        Text(text)
            .font(CarpenterFont.bubble)
            .foregroundStyle(isMine ? palette.textOnSentBubble : palette.textOnAccentTint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                BubbleShape(isMine: isMine, position: position)
                    .fill(isMine ? palette.sentBubbleFill : palette.accentTint))
    }
}

public struct BubbleShape: Shape {
    public let isMine: Bool
    public let position: BubblePosition

    public init(isMine: Bool, position: BubblePosition) {
        self.isMine = isMine
        self.position = position
    }

    public func path(in rect: CGRect) -> Path {
        let full = CarpenterMetrics.bubbleRadius(forHeight: rect.height)
        let tail = position.hasTail ? min(CarpenterMetrics.bubbleTailRadius, full) : full

        return UnevenRoundedRectangle(
            topLeadingRadius: full,
            bottomLeadingRadius: isMine ? full : tail,
            bottomTrailingRadius: isMine ? tail : full,
            topTrailingRadius: full,
            style: .continuous
        ).path(in: rect)
    }
}

struct ViewedMedia: Identifiable {
    let loaded: LoadedMedia
    let message: Message
    var id: MessageID { message.id }
}

public struct MessageRunView: View {
    @Environment(\.palette) private var palette
    @Environment(\.bubbleMaxWidth) private var bubbleMaxWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.showsAvatars) private var showsAvatars
    @Environment(\.showsRunAuthors) private var showsRunAuthors

    private let run: MessageRun
    private let onHide: ((MessageID) async -> Void)?
    private let actions: MessageActions?
    private let onShowDetail: ((Message) -> Void)?

    @State fileprivate var editing: Message?
    @State fileprivate var withdrawing: Message?
    @State fileprivate var hiding: Message?
    @State private var problem: String?
    @State fileprivate var reacting: Message?
    @State fileprivate var viewing: ViewedMedia?
    @State fileprivate var reporting: Message?
    @State fileprivate var blocking: Member?
    @State fileprivate var listingReactionsOf: Message?
    @State private var pickingFor: Message?
    @State private var editDetent: PresentationDetent = .large
    @State private var favourites = FavouriteEmoji()
    private let onSeen: ((MessageID) async -> Void)?
    private let delay: (MessageID) -> TimeInterval?

    public init(
        run: MessageRun,
        onHide: ((MessageID) async -> Void)? = nil,
        actions: MessageActions? = nil,
        onShowDetail: ((Message) -> Void)? = nil,
        onSeen: ((MessageID) async -> Void)? = nil,
        delay: @escaping (MessageID) -> TimeInterval? = { _ in nil }
    ) {
        self.run = run
        self.onHide = onHide
        self.actions = actions
        self.onShowDetail = onShowDetail
        self.onSeen = onSeen
        self.delay = delay
    }

    public var body: some View {
        content
            .presentingViewer($viewing) { viewed in
                MediaViewerView(
                    loaded: viewed.loaded, item: ViewedItem(viewed.message),
                    onReport: { reporting = viewed.message })
            }
            .sizedSheet(item: $reporting) { message in
                ReportView(item: ViewedItem(message))
            }
            .sizedSheet(item: $listingReactionsOf) { message in
                ReactionListView(
                    message: message,
                    member: { actions?.member($0) },
                    onToggle: { emoji in
                        if let emoji { favourites.record(emoji) }
                        await actions?.react(message.id, emoji)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .confirmingBlock($blocking) { person in await actions?.block?(person) }
            .sizedSheet(item: $editing) { message in
                EditWordsView(
                    title: Text("Edit message", bundle: .module),
                    placeholder: Text("Your message", bundle: .module),
                    current: message.body
                ) { text in
                    await actions?.edit(message.id, text)
                }
                .presentationDetents([.medium, .large], selection: $editDetent)
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                hiding.map { quoted($0) } ?? Text("Hide this?", bundle: .module),
                isPresented: Binding(
                    get: { hiding != nil },
                    set: { if !$0 { hiding = nil } }),
                titleVisibility: .visible,
                presenting: hiding
            ) { message in
                Button(role: .destructive) {
                    hiding = nil
                    Task { await onHide?(message.id) }
                } label: {
                    Text("Hide for me", bundle: .module)
                }
                Button(role: .cancel) { hiding = nil } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: { _ in
                Text(
                    "Only you stop seeing it, on all of your devices. Nobody else is affected and nobody is told. You can show it again.",
                    bundle: .module)
            }
            .alert(
                Text("Withdraw this message?", bundle: .module),
                isPresented: Binding(
                    get: { withdrawing != nil },
                    set: { if !$0 { withdrawing = nil } }),
                presenting: withdrawing
            ) { message in
                Button(role: .destructive) {
                    Task { problem = await actions?.withdraw(message.id) }
                    withdrawing = nil
                } label: {
                    Text("Withdraw it", bundle: .module)
                }
                Button(role: .cancel) { withdrawing = nil } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: { _ in
                Text(
                    "Everybody stops seeing the words. Nothing is erased from anybody's device — each copy shows that a message was withdrawn.",
                    bundle: .module)
            }
            .alert(
                Text("That did not go through", bundle: .module),
                isPresented: Binding(
                    get: { problem != nil }, set: { if !$0 { problem = nil } })
            ) {
                Button { problem = nil } label: { Text("OK", bundle: .module) }
            } message: {
                Text(verbatim: problem ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if run.isMine {
            VStack(alignment: .trailing, spacing: 3) {
                bubbles
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                if showsAvatars {
                    NavigationLink(value: PersonRoute(run.author.id)) {
                        PersonAvatarView(
                            member: run.author,
                            diameter: CarpenterMetrics.messageAvatar,
                            usesStrongFill: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        Text("About \(run.author.displayName)", bundle: .module))
                }
                VStack(alignment: .leading, spacing: 3) {
                    if showsRunAuthors {
                        Text(run.author.displayName)
                            .font(CarpenterFont.micro)
                            .foregroundStyle(palette.tertiaryText)
                            .padding(.leading, 12)
                    }
                    bubbles
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var bubbles: some View {
        ForEach(Array(run.messages.enumerated()), id: \.element.id) { index, message in
            VStack(alignment: run.isMine ? .trailing : .leading, spacing: 0) {
                bubble(for: message, at: index)
                .accessibilityAction(named: Text("React", bundle: .module)) { reacting = message }
                .overlay(alignment: run.isMine ? .topLeading : .topTrailing) {
                    if !message.reactions.isEmpty {
                        MessageReactions(
                            reactions: message.reactions,
                            mine: message.myReaction,
                            onToggle: { emoji in
                                if let emoji { favourites.record(emoji) }
                                await actions?.react(message.id, emoji)
                            },
                            onOpen: { listingReactionsOf = message }
                        )
                        .offset(
                            x: (run.isMine ? -1 : 1) * 14,
                            y: -MessageReactions.diameter * 0.75)
                    }
                }
                .padding(.top, message.reactions.isEmpty ? 0 : MessageReactions.diameter * 0.75 + 2)
                .frame(maxWidth: bubbleMaxWidth, alignment: run.isMine ? .trailing : .leading)
                .onAppear { if !run.isMine { Task { await onSeen?(message.id) } } }
                .onLongPressGesture { reacting = message }
                .popover(item: $reacting) { held in
                    MessageTapbackBar(
                        favourites: favourites.emoji,
                        chosen: held.myReaction,
                        onPick: { emoji in
                            if let emoji { favourites.record(emoji) }
                            reacting = nil
                            await actions?.react(held.id, emoji)
                        },
                        onMoreEmoji: {
                            reacting = nil
                            pickingFor = held
                        },
                        actions: { menu(for: held) }
                    )
                    .presentationCompactAdaptation(.popover)
                }
                .emojiPicker(item: $pickingFor) { held, emoji in
                    pickingFor = nil
                    favourites.record(emoji)
                    Task { await actions?.react(held.id, emoji) }
                }

                if let seconds = delay(message.id) {
                    Text(DebugDelayFormatter.text(seconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette.tertiaryText)
                        .padding(.top, 2)
                }

                if run.isMine, index == run.messages.count - 1 || message.notGone != nil {
                    DeliveryMarkView(
                        delivery: message.delivery, isEdited: message.isEdited,
                        notGone: message.notGone, sentAt: message.sentAt)
                } else if message.isEdited {
                    DeliveryMarkView(delivery: .pending, isEdited: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: run.isMine ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .transition(
                reduceMotion ? .opacity : .messageArrival(isMine: run.isMine))
        }
    }
}

extension MessageRunView {
    @ViewBuilder
    fileprivate func bubble(for message: Message, at index: Int) -> some View {
        if let media = message.media, !message.isWithdrawn {
            MediaBubbleView(
                message: message, media: media, isMine: run.isMine,
                position: run.position(at: index),
                onOpen: { viewing = ViewedMedia(loaded: $0, message: message) })
        } else {
            MessageBubbleView(text: message.body, isMine: run.isMine, position: run.position(at: index))
        }
    }

    @ViewBuilder
    fileprivate func menu(for message: Message) -> some View {
        if let onShowDetail {
            Button { onShowDetail(message) } label: {
                Label {
                    Text("Details", bundle: .module)
                } icon: {
                    Image(systemName: "info.circle")
                }
            }
        }

        if !message.isMine {
            Button {
                reacting = nil
                reporting = message
            } label: {
                Label {
                    Text("Report", bundle: .module)
                } icon: {
                    Image(systemName: "flag")
                }
            }

            if actions?.block != nil {
                Button(role: .destructive) {
                    reacting = nil
                    blocking = message.author
                } label: {
                    Label {
                        Text("Block \(message.author.displayName)", bundle: .module)
                    } icon: {
                        Image(systemName: "hand.raised")
                    }
                }
                .tint(palette.destructive)
            }
        }

        if let actions, !message.isWithdrawn {
            if actions.editableFor(message.id) != nil {
                Button { editing = message } label: {
                    Label {
                        Text("Edit", bundle: .module)
                    } icon: {
                        Image(systemName: "pencil")
                    }
                }
            }

            if actions.withdrawableFor(message.id) != nil {
                Button(role: .destructive) { withdrawing = message } label: {
                    Label {
                        Text("Withdraw", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
                .tint(palette.destructive)
            }
        }

        if onHide != nil {
            Button(role: .destructive) {
                hiding = message
            } label: {
                Label {
                    Text("Hide for me", bundle: .module)
                } icon: {
                    Image(systemName: "eye.slash")
                }
            }
            .tint(palette.destructive)
        }
    }
}

extension MessageRunView {
    fileprivate func quoted(_ message: Message) -> Text {
        let words = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return Text("Hide this?", bundle: .module) }
        let short = words.count > 60 ? String(words.prefix(60)) + "…" : words
        return Text("Hide \u{201C}\(short)\u{201D}?", bundle: .module)
    }
}

extension View {
    fileprivate func presentingViewer(
        _ item: Binding<ViewedMedia?>, @ViewBuilder content: @escaping (ViewedMedia) -> some View
    ) -> some View {
        #if os(iOS)
            fullScreenCover(item: item, content: content)
        #else
            sheet(item: item, content: content)
        #endif
    }
}

extension AnyTransition {
    static func messageArrival(isMine: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.9, anchor: isMine ? .bottomTrailing : .bottomLeading)
                .combined(with: .offset(y: 8))
                .combined(with: .opacity),
            removal: .opacity)
    }
}

extension View {
    func measuringBubbleWidth() -> some View {
        modifier(BubbleWidthModifier())
    }
}

private struct BubbleWidthModifier: ViewModifier {
    @State private var available: CGFloat?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
            .environment(
                \.bubbleMaxWidth,
                available.map { $0 * CarpenterMetrics.bubbleMaxWidthFraction } ?? .infinity
            )
    }
}

struct EditWordsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @FocusState private var writing: Bool

    let title: Text
    let placeholder: Text
    let current: String
    let onSave: (String) async -> String?

    @State private var text: String = ""
    @State private var saving = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            title
                .font(CarpenterFont.rowTitle)
                .foregroundStyle(palette.primaryText)

            TextField(text: $text, axis: .vertical) {
                placeholder
            }
            .textFieldStyle(.plain)
            .font(CarpenterFont.bubble)
            .foregroundStyle(palette.primaryText)
            .lineLimit(1...6)
            .focused($writing)
            .doneAboveKeyboard($writing)
            .fieldChrome(isFocused: writing)
            .contentShape(.rect)
            .onTapGesture { if !writing { writing = true } }

            if let problem {
                Text(verbatim: problem)
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.destructive)
            }

            Text("Everybody sees the new words, and that it was edited.", bundle: .module)
                .font(CarpenterFont.caption)
                .foregroundStyle(palette.secondaryText)

            Button {
                Task {
                    saving = true
                    problem = await onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    saving = false
                    if problem == nil { dismiss() }
                }
            } label: {
                Text("Save", bundle: .module).primaryAction()
            }
            .prominentActionButton()
            .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background.ignoresSafeArea())
        .onAppear {
            text = current
            writing = true
        }
    }
}
