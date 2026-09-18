import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

public struct OutpostView: View {
    @Environment(\.palette) private var palette

    private let owner: Member
    private let posts: [OutpostPost]
    private let audiencePeople: Int
    private let isViewer: Bool
    private let onPost: (String) async -> String?
    private let onAttach: (([PickedMedia], String?) async -> String?)?
    private let postActions: PostActions?
    private let audience: OutpostAudience
    private let reciprocal: ReciprocalAccess?
    private let settings: OutpostDetailSettings?
    private let onChangeAccess: ((ParticipantID, OutpostAccessChoice, RoomID?) async -> String?)?
    private let onSeen: (() async -> Void)?
    private let blurb: String?
    private let onPerson: ((ReciprocalAccess) -> Void)?
    private let onReact: (OutpostPost, String?) async -> Void
    private let canJoinIn: Bool
    private let onRefresh: () async -> Void
    private let onPicture: ((PickedAvatar, OutpostPictureReach) async -> Void)?

    @State private var isComposing = false
    @State private var query = ""
    @State private var isSearching = false
    @State private var deciding: OutpostAccessSubject?
    @State private var accessProblem: String?
    @State private var pickedPicture: PhotosPickerItem?
    @State private var decidingReach: PickedAvatar?

    public init(
        owner: Member,
        posts: [OutpostPost],
        audiencePeople: Int,
        isViewer: Bool = true,
        onPost: @escaping (String) async -> String? = { _ in nil },
        onAttach: (([PickedMedia], String?) async -> String?)? = nil,
        postActions: PostActions? = nil,
        audience: OutpostAudience = OutpostAudience(),
        reciprocal: ReciprocalAccess? = nil,
        onChangeAccess: ((ParticipantID, OutpostAccessChoice, RoomID?) async -> String?)? = nil,
        onSeen: (() async -> Void)? = nil,
        blurb: String? = nil,
        settings: OutpostDetailSettings? = nil,
        onPerson: ((ReciprocalAccess) -> Void)? = nil,
        onRefresh: @escaping () async -> Void = {},
        onReact: @escaping (OutpostPost, String?) async -> Void = { _, _ in },
        canJoinIn: Bool = true,
        onPicture: ((PickedAvatar, OutpostPictureReach) async -> Void)? = nil
    ) {
        self.onPicture = onPicture
        self.reciprocal = reciprocal
        self.settings = settings
        self.onChangeAccess = onChangeAccess
        self.onSeen = onSeen
        self.blurb = blurb
        self.onPerson = onPerson
        self.onRefresh = onRefresh
        self.onReact = onReact
        self.canJoinIn = canJoinIn
        self.owner = owner
        self.posts = posts
        self.audiencePeople = audiencePeople
        self.isViewer = isViewer
        self.onPost = onPost
        self.onAttach = onAttach
        self.postActions = postActions
        self.audience = audience
    }

    private var pushesAudience: Bool {
        #if os(macOS)
            false
        #else
            isViewer
        #endif
    }

    public var body: some View {
        List {
            Section {
                VStack(spacing: 0) {
                    OutpostHeaderView(
                        person: owner, blurb: blurb, isViewer: isViewer,
                        picking: onPicture == nil ? nil : $pickedPicture)
                    OutpostHeaderDivider()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if isViewer {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        composer

                        if let audience = AudienceSummary.line(people: audiencePeople) {
                            Text(audience)
                                .font(CarpenterFont.caption)
                                .foregroundStyle(palette.quaternaryText)
                                .padding(.leading, 16)
                        }
                    }
                    .listRowInsets(
                        EdgeInsets(
                            top: 10, leading: CarpenterMetrics.screenMargin, bottom: 12,
                            trailing: CarpenterMetrics.screenMargin))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            ForEach(shown) { post in
                PostRow(
                    post: post, actions: postActions, viewer: owner.id, onReact: onReact,
                    isReadOnly: !canJoinIn)
                    .listRowInsets(
                        EdgeInsets(
                            top: 0, leading: CarpenterMetrics.screenMargin, bottom: 0,
                            trailing: CarpenterMetrics.screenMargin))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden, edges: .top)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(palette.background)
        .refreshable { await onRefresh() }
        .searchable(
            text: $query, isPresented: $isSearching,
            prompt: Text("Search posts", bundle: .module))
        .onChange(of: isSearching) { _, searching in
            if !searching { query = "" }
        }
        .overlay {
            if shown.isEmpty, !query.isEmpty {
                ContentUnavailableView.search(text: query)
                    .background(palette.background)
            }
        }
        .tint(palette.accentColor)
        .navigationTitle(Text(verbatim: ""))
        .toolbarTitleDisplayMode(.inline)
        .task { await onSeen?() }
        .outpostAccessSheet(deciding: $deciding) { person, choice in
            await onChangeAccess?(person, choice, nil)
        }
        .alert(
            Text("That did not go through", bundle: .module),
            isPresented: Binding(
                get: { accessProblem != nil }, set: { if !$0 { accessProblem = nil } })
        ) {
            Button { accessProblem = nil } label: { Text("OK", bundle: .module) }
        } message: {
            Text(verbatim: accessProblem ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isSearching = true } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(palette.primaryText)
                }
                .accessibilityLabel(Text("Search posts", bundle: .module))
                .barIconLargeContent(Text("Search posts", bundle: .module), systemImage: "magnifyingglass")
                .disabled(posts.isEmpty)
            }
            if let settings {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        OutpostDetailSettingsView(
                            person: settings.person, isNotified: settings.isNotified,
                            acrossAllOutposts: settings.acrossAllOutposts,
                            onSetNotified: settings.onSetNotified)
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(palette.primaryText)
                    }
                    .accessibilityLabel(Text("Outpost settings", bundle: .module))
                }
            }
            if pushesAudience {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        OutpostAudienceView(audience)
                    } label: {
                        Image(systemName: "person.2.badge.key")
                            .foregroundStyle(palette.primaryText)
                    }
                    .accessibilityLabel(Text("Who sees it", bundle: .module))
                    .barIconLargeContent(Text("Who sees it", bundle: .module), systemImage: "person.2.badge.key")
                }
            } else if !isViewer, let reciprocal, let onPerson {
                ToolbarItem(placement: .primaryAction) {
                    Button { onPerson(reciprocal) } label: {
                        Image(systemName: "person.2.badge.key")
                            .foregroundStyle(palette.primaryText)
                    }
                    .accessibilityLabel(
                        Text("What each of you can read", bundle: .module))
                    .barIconLargeContent(
                        Text("What each of you can read", bundle: .module),
                        systemImage: "person.2.badge.key")
                }
            }
        }
        .sizedSheet(isPresented: $isComposing) {
            PostComposerView(onAttach: onAttach) { body in await onPost(body) }
                .themed(.default)
        }
        .croppingPickedPhoto($pickedPicture) { picked in decidingReach = picked }
        .confirmationDialog(
            Text("Use this picture where?", bundle: .module),
            isPresented: Binding(
                get: { decidingReach != nil }, set: { if !$0 { decidingReach = nil } }),
            titleVisibility: .visible
        ) {
            Button {
                if let picked = decidingReach {
                    decidingReach = nil
                    Task { await onPicture?(picked, .outpostOnly) }
                }
            } label: {
                Text("Just on my Outpost", bundle: .module)
            }
            Button {
                if let picked = decidingReach {
                    decidingReach = nil
                    Task { await onPicture?(picked, .everywhere) }
                }
            } label: {
                Text("Everywhere", bundle: .module)
            }
            Button(role: .cancel) { decidingReach = nil } label: {
                Text("Cancel", bundle: .module)
            }
        } message: {
            Text(
                "Just on your Outpost leaves your rooms showing the photo from You. Everywhere changes both.",
                bundle: .module)
        }
    }

    private var shown: [OutpostPost] {
        guard !query.isEmpty else { return posts }
        return posts.filter { $0.body.localizedStandardContains(query) }
    }

    private var composer: some View {
        HStack(spacing: 11) {
            Button { isComposing = true } label: {
                Text("Post to your Outpost", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(palette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(minHeight: CarpenterMetrics.composerControlHeight)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(minHeight: CarpenterMetrics.hitTarget)
            .contentShape(Capsule())
        }
    }
}

private struct PostRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.clock) private var clock

    let post: OutpostPost
    let actions: PostActions?
    let viewer: ParticipantID
    let onReact: (OutpostPost, String?) async -> Void
    let isReadOnly: Bool

    var body: some View {
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

            if let latest = post.previewComments.last {
                Text(
                    "**\(latest.author.displayName)** \(PostFormatting.plainText(latest.body))"
                )
                .font(CarpenterFont.comment)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }

            ReactionBar(
                reactions: post.reactions, viewer: viewer, commentCount: post.commentCount,
                onReact: { await onReact(post, $0) }, thread: post,
                isReadOnly: isReadOnly && !post.isMine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .postActions(
            ViewedItem(post), isWithdrawn: post.isWithdrawn, kind: .post, actions: actions)
    }
}

#if DEBUG
    #Preview("04 Outpost — dark") {
        NavigationStack {
            OutpostView(
                owner: Fixtures.cassilda,
                posts: Fixtures.posts,
                audiencePeople: Fixtures.audiencePeople)
        }
        .environment(\.clock, Fixtures.PreviewClock())
        .themed(.cobalt)
        .preferredColorScheme(.dark)
    }

    #Preview("04 Outpost — light") {
        NavigationStack {
            OutpostView(
                owner: Fixtures.cassilda,
                posts: Fixtures.posts,
                audiencePeople: Fixtures.audiencePeople
            )
        }
        .environment(\.clock, Fixtures.PreviewClock())
        .themed(.signalAmber)
        .preferredColorScheme(.light)
    }
#endif
