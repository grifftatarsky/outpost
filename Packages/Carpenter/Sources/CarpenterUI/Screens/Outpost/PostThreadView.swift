import CarpenterKit
import SwiftUI

public struct PostThreadView: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.clock) private var clock

    @State private var draft = ""
    @State private var explaining = false

    private let post: OutpostPost
    private let comments: [OutpostComment]
    private let viewer: ParticipantID
    private let onComment: (String) async -> Void
    private let onReactToPost: (String?) async -> Void
    private let onReactToComment: (OutpostComment, String?) async -> Void
    private let canJoinIn: Bool
    private let hidden: Int
    private let settings: OutpostSettings
    private let postActions: PostActions?

    public init(
        post: OutpostPost,
        comments: [OutpostComment],
        viewer: ParticipantID,
        onComment: @escaping (String) async -> Void = { _ in },
        onReactToPost: @escaping (String?) async -> Void = { _ in },
        onReactToComment: @escaping (OutpostComment, String?) async -> Void = { _, _ in },
        canJoinIn: Bool = true,
        hidden: Int = 0,
        settings: OutpostSettings = OutpostSettings(),
        postActions: PostActions? = nil
    ) {
        self.post = post
        self.comments = comments
        self.viewer = viewer
        self.onComment = onComment
        self.onReactToPost = onReactToPost
        self.onReactToComment = onReactToComment
        self.canJoinIn = canJoinIn
        self.hidden = hidden
        self.settings = settings
        self.postActions = postActions
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    original
                    Rectangle()
                        // divides regions: the post from the thread answering it
                        .fill(palette.separator)
                        .frame(height: CarpenterMetrics.hairline)

                    ForEach(comments) { comment in
                        CommentRow(
                            comment: comment,
                            viewer: viewer,
                            onReact: { await onReactToComment(comment, $0) },
                            actions: postActions,
                            isReadOnly: !canJoinIn
                        )
                    }

                    // COPY BEGIN 2e756da5 [NEEDS HUMAN REVIEW]
                    if comments.isEmpty, hidden == 0 {
                        Text("No comments yet.", bundle: .module)
                            .font(CarpenterFont.footnote)
                            .foregroundStyle(palette.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 28)
                    }
                    // COPY END 2e756da5

                    if hidden > 0 { missing }
                }
                .padding(.bottom, 16)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollDismissesKeyboard(.interactively)

            if canJoinIn { composer }
        }
        .background(palette.background.ignoresSafeArea())
        // COPY BEGIN 98fde6ab [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Post", bundle: .module))
        // COPY END 98fde6ab
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $explaining) {
            HiddenCommentsSheet(hidden: hidden, settings: settings)
                .themed(.default)
        }
    }

    private var missing: some View {
        Button { explaining = true } label: {
            // COPY BEGIN f9a63942 [NEEDS HUMAN REVIEW]
            HStack(spacing: 6) {
                (hidden == 1
                    ? Text("1 comment is not shown", bundle: .module)
                    : Text("\(hidden) comments are not shown", bundle: .module))
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.tertiaryText)
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(palette.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 4)
            // COPY END f9a63942
        }
        .buttonStyle(.plain)
        .tappable()
        // COPY BEGIN 16a411ef [NEEDS HUMAN REVIEW]
        .accessibilityLabel(Text("Why some comments are not shown", bundle: .module))
        // COPY END 16a411ef
    }

    private var original: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(post.author.displayName)
                    .font(CarpenterFont.postAuthor)
                    .foregroundStyle(palette.primaryText)
                Text(RelativeTimestampFormatter().compact(for: post.postedAt, now: clock.now))
                    .font(CarpenterFont.postDetail)
                    .foregroundStyle(palette.tertiaryText)
                if post.editedAt != nil { EditedMark() }
            }

            if !post.media.isEmpty {
                PostPicturesView(post: post, media: post.media)
            }

            if !post.body.isEmpty {
                FormattedText(source: post.body)
                    .font(CarpenterFont.postBody)
                    .foregroundStyle(palette.primaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ReactionBar(
                reactions: post.reactions, viewer: viewer, onReact: onReactToPost,
                isReadOnly: !canJoinIn)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CarpenterMetrics.screenMargin)
        .padding(.vertical, 16)
        .postActions(
            ViewedItem(post), isWithdrawn: post.isWithdrawn, kind: .post, actions: postActions)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 4) {
            TextField(text: $draft, axis: .vertical) {
                // COPY BEGIN 76144bc4 [NEEDS HUMAN REVIEW]
                Text("Add a comment", bundle: .module)
                // COPY END 76144bc4
            }
            .textFieldStyle(.plain)
            .font(CarpenterFont.bubble)
            .foregroundStyle(palette.primaryText)
            .padding(.leading, 14)
            .padding(.vertical, 8)
            .lineLimit(1...6)
            .onSubmit {
                let outgoing = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !outgoing.isEmpty else { return }
                draft = ""
                Task { await onComment(outgoing) }
            }

            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    let outgoing = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft = ""
                    Task { await onComment(outgoing) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(palette.accentFill, in: .circle)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .padding(.bottom, 4)
                .transition(.scale.combined(with: .opacity))
                // COPY BEGIN 650327b8 [NEEDS HUMAN REVIEW]
                .accessibilityLabel(Text("Post comment", bundle: .module))
                // COPY END 650327b8
            }
        }
        .glassEffect(
            .regular,
            in: RoundedRectangle(
                cornerRadius: CarpenterMetrics.composerFieldRadius, style: .continuous))
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.2),
            value: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct CommentRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.clock) private var clock

    let comment: OutpostComment
    let viewer: ParticipantID
    let onReact: (String?) async -> Void
    let actions: PostActions?
    let isReadOnly: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            PersonAvatarView(member: comment.author, diameter: 32, onOutpost: true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(comment.author.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    Text(
                        RelativeTimestampFormatter().compact(for: comment.postedAt, now: clock.now)
                    )
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.tertiaryText)
                    if comment.editedAt != nil { EditedMark() }
                }

                FormattedText(source: comment.body)
                    .font(CarpenterFont.comment)
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ReactionBar(
                    reactions: comment.reactions, viewer: viewer, onReact: onReact,
                    isReadOnly: isReadOnly)
            }
        }
        .padding(.horizontal, CarpenterMetrics.screenMargin)
        .padding(.vertical, 12)
        .postActions(
            ViewedItem(comment), isWithdrawn: comment.isWithdrawn, kind: .comment,
            actions: actions)
    }
}

#if DEBUG
    #Preview("43 Post and comments — dark") {
        NavigationStack {
            PostThreadView(
                post: Fixtures.feed[1],
                comments: [
                    OutpostComment(
                        id: PostID(entry: Fixtures.hash(31)), author: Fixtures.hastur,
                        body: "a balloon that made a decision", postedAt: Fixtures.ago(minutes: 40),
                        reactions: ["🎈": [Fixtures.cassilda.id]]),
                    OutpostComment(
                        id: PostID(entry: Fixtures.hash(32)), author: Fixtures.camilla,
                        body: "putting this on the Gazette masthead",
                        postedAt: Fixtures.ago(minutes: 12)),
                ],
                viewer: Fixtures.cassilda.id
            )
        }
        .environment(\.clock, Fixtures.PreviewClock())
        .themed(.cobalt)
        .preferredColorScheme(.dark)
    }
#endif
