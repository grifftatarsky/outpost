import CarpenterKit
import SwiftUI

public struct OutpostFeedView: View {
    @Environment(\.palette) private var palette
    @Environment(\.showsPeopleRail) private var showsPeopleRail
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let viewer: Member
    private let authors: [Member]
    private let posts: [OutpostPost]
    private let onReact: (OutpostPost, String?) async -> Void
    private let canJoinIn: Bool
    private let onPost: (String) async -> String?
    private let onAttach: (([PickedMedia], String?) async -> String?)?
    private let postActions: PostActions?
    private let unseen: Set<ParticipantID>
    private let showsAllOutposts: Bool
    private let onSeen: ((OutpostPost) async -> Void)?

    @State private var query = ""
    @State private var isComposing = false
    @State private var tag: String?

    private var shown: [OutpostPost] {
        var result = posts
        if let tag { result = result.filter { PostTags.text($0.body, has: tag) } }
        guard !query.isEmpty else { return result }
        let q = query.hasPrefix("#") ? String(query.dropFirst()) : query
        return result.filter { post in
            post.body.localizedStandardContains(query)
                || post.author.displayName.localizedStandardContains(query)
                || PostTags.tags(in: post.body).contains { PostTags.canonical($0) == PostTags.canonical(q) }
        }
    }

    public init(
        viewer: Member,
        authors: [Member],
        posts: [OutpostPost],
        onReact: @escaping (OutpostPost, String?) async -> Void = { _, _ in },
        onPost: @escaping (String) async -> String? = { _ in nil },
        onAttach: (([PickedMedia], String?) async -> String?)? = nil,
        postActions: PostActions? = nil,
        unseen: Set<ParticipantID> = [],
        showsAllOutposts: Bool = false,
        onSeen: ((OutpostPost) async -> Void)? = nil,
        canJoinIn: Bool = true
    ) {
        self.viewer = viewer
        self.authors = authors
        self.posts = posts
        self.onReact = onReact
        self.canJoinIn = canJoinIn
        self.onPost = onPost
        self.onAttach = onAttach
        self.postActions = postActions
        self.unseen = unseen
        self.showsAllOutposts = showsAllOutposts
        self.onSeen = onSeen
    }

    private var leadingPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .topBarLeading
        #else
            .navigation
        #endif
    }

    private var trailingPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .topBarTrailing
        #else
            .automatic
        #endif
    }

    public var body: some View {
        Group {
            if posts.isEmpty {
                emptyState
            } else {
                List {
                    if showsPeopleRail {
                        PeopleRail(viewer: viewer, authors: authors, unseen: unseen)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    ForEach(shown) { post in
                        FeedPostRow(
                            post: post, viewer: viewer, onReact: onReact, actions: postActions,
                            canJoinIn: canJoinIn)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden, edges: .top)
                            .onAppear { Task { await onSeen?(post) } }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .overlay {
                    if shown.isEmpty {
                        if let tag {
                            ContentUnavailableView(
                                label: { Label { Text("No posts tagged #\(tag)", bundle: .module) } icon: { Image(systemName: "number") } }
                            )
                            .background(palette.background)
                        } else if !query.isEmpty {
                            ContentUnavailableView.search(text: query)
                                .background(palette.background)
                        }
                    }
                }
            }
        }
        .background(palette.background)
        .navigationTitle(Text("Outposts", bundle: .module))
        .helpButton()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            #if !os(macOS)
                ToolbarItem(placement: .principal) {
                    Text("Outposts", bundle: .module).font(.headline)
                }
            #endif
            ToolbarItem(placement: leadingPlacement) {
                Button { isComposing = true } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(palette.primaryText)
                }
                .accessibilityLabel(Text("New post", bundle: .module))
                .barIconLargeContent(Text("New post", bundle: .module), systemImage: "square.and.pencil")
            }
            if showsAllOutposts {
                ToolbarItem(placement: trailingPlacement) {
                    Menu {
                        NavigationLink(value: AllOutpostsRoute()) {
                            Label {
                                Text("All Outposts", bundle: .module)
                            } icon: {
                                Image(systemName: "list.bullet")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 21, weight: .regular))
                            .foregroundStyle(palette.primaryText)
                    }
                    .accessibilityLabel(Text("More", bundle: .module))
                }
            }
        }
        .sizedSheet(isPresented: $isComposing) {
            PostComposerView(onAttach: onAttach) { body in await onPost(body) }
        }
        .environment(
            \.openURL,
            OpenURLAction { url in
                guard url.scheme == FormattedText.tagScheme else { return .systemAction }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    tag = url.host() ?? url.absoluteString
                }
                return .handled
            }
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let tag {
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { self.tag = nil }
                        } label: {
                            HStack(spacing: 5) {
                                Text(verbatim: "#\(tag)")
                                    .font(CarpenterFont.badge)
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                        .buttonStyle(.glass)
                        .tint(palette.accentColor)
                        .accessibilityLabel(Text("Stop filtering by #\(tag)", bundle: .module))

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, CarpenterMetrics.screenMargin)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("Nothing here yet", bundle: .module)
            } icon: {
                Image(systemName: "rectangle.stack")
            }
        } description: {
            Text(
                "Somebody's Outpost appears here once they give you access to it.",
                bundle: .module)
        }
        .background(palette.background)
    }
}

extension EnvironmentValues {
    @Entry var showsPeopleRail = true
}

private struct PeopleRail: View {
    @Environment(\.palette) private var palette

    let viewer: Member
    let authors: [Member]
    var unseen: Set<ParticipantID> = []

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                NavigationLink(value: viewer.id) {
                    person(viewer, label: Text("You", bundle: .module), isViewer: true)
                }
                .buttonStyle(.plain)

                ForEach(ordered) { author in
                    NavigationLink(value: author.id) {
                        person(author, label: Text(author.displayName), isViewer: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
    }

    private var ordered: [Member] {
        authors.filter { $0.id != viewer.id }
            .sorted { left, right in
                let leftNew = unseen.contains(left.id)
                if leftNew != unseen.contains(right.id) { return leftNew }
                return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
            }
    }

    private func person(_ member: Member, label: Text, isViewer: Bool) -> some View {
        VStack(spacing: 6) {
            PersonAvatarView(member: member, diameter: 52, isAccented: isViewer, onOutpost: true)
                .padding(Self.ringInset)
                .overlay {
                    if !isViewer {
                        Circle()
                            .strokeBorder(
                                unseen.contains(member.id)
                                    ? palette.accentColor : palette.separator,
                                lineWidth: unseen.contains(member.id) ? 2.5 : 1.5)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isViewer {
                        Circle()
                            .fill(palette.accentFill)
                            .frame(width: 20, height: 20)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(palette.textOnSentBubble)
                            }
                            .overlay { Circle().strokeBorder(palette.background, lineWidth: 2.5) }
                            .offset(x: 2 - Self.ringInset, y: 2 - Self.ringInset)
                    }
                }

            label
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.neutralText)
                .lineLimit(1)
        }
        .frame(width: 52 + Self.ringInset * 2)
    }

    private static let ringInset: CGFloat = 5
}

private struct FeedPostRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.clock) private var clock

    let post: OutpostPost
    let viewer: Member
    let onReact: (OutpostPost, String?) async -> Void
    let actions: PostActions?
    let canJoinIn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            PersonAvatarView(member: post.author, diameter: 40, isAccented: post.isMine, onOutpost: true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Group {
                        if post.isMine {
                            Text("You", bundle: .module)
                        } else {
                            Text(post.author.displayName)
                        }
                    }
                    .font(CarpenterFont.postAuthor)
                    .foregroundStyle(palette.primaryText)

                    Text(RelativeTimestampFormatter().compact(for: post.postedAt, now: clock.now))
                        .font(CarpenterFont.postDetail)
                        .foregroundStyle(palette.tertiaryText)

                    if post.editedAt != nil { EditedMark() }

                    Spacer(minLength: 0)
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
                    reactions: post.reactions,
                    viewer: viewer.id,
                    commentCount: post.commentCount,
                    onReact: { await onReact(post, $0) },
                    thread: post,
                    isReadOnly: !canJoinIn && !post.isMine
                )
            }
        }
        .padding(.horizontal, CarpenterMetrics.screenMargin)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .postActions(
            ViewedItem(post), isWithdrawn: post.isWithdrawn, kind: .post, actions: actions)
    }
}

#if DEBUG
    #Preview("41 Outpost feed — dark") {
        NavigationStack {
            OutpostFeedView(
                viewer: Fixtures.cassilda,
                authors: [Fixtures.cassilda, Fixtures.hastur, Fixtures.camilla],
                posts: Fixtures.feed
            )
        }
        .environment(\.clock, Fixtures.PreviewClock())
        .themed(.cobalt)
        .preferredColorScheme(.dark)
    }
#endif
