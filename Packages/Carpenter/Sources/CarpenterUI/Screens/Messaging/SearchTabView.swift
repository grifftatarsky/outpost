import CarpenterKit
import SwiftUI

public struct SearchTabView: View {
    @Environment(\.palette) private var palette

    // COPY BEGIN 8a53b455 [NEEDS HUMAN REVIEW]
    public enum Scope: Hashable, CaseIterable, Sendable {
        case everything, messages, photos, outposts

        var label: LocalizedStringKey {
            switch self {
            case .everything: return "All"
            case .messages: return "Messages"
            case .photos: return "Photos"
            case .outposts: return "Outposts"
            }
        }
    }
    // COPY END 8a53b455

    private let onSearch: (String) -> SearchResults
    private let onOpenRoom: (RoomID) -> Void
    private let onOpenMessage: (RoomID, MessageID) -> Void
    private let onOpenPost: (OutpostPost) -> Void

    @State private var query = ""
    @State private var scope: Scope = .everything
    @FocusState private var searching: Bool
    @State private var results = SearchResults()

    public init(
        onSearch: @escaping (String) -> SearchResults,
        onOpenRoom: @escaping (RoomID) -> Void,
        onOpenMessage: @escaping (RoomID, MessageID) -> Void,
        onOpenPost: @escaping (OutpostPost) -> Void
    ) {
        self.onSearch = onSearch
        self.onOpenRoom = onOpenRoom
        self.onOpenMessage = onOpenMessage
        self.onOpenPost = onOpenPost
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var conversations: [SearchResults.Conversation] {
        scope == .everything || scope == .messages ? results.conversations : []
    }
    private var said: [SearchResults.Said] {
        scope == .everything || scope == .messages ? results.said : []
    }
    private var pictures: [SearchResults.Picture] {
        scope == .everything || scope == .photos ? results.pictures : []
    }
    private var posts: [OutpostPost] {
        scope == .everything || scope == .outposts ? results.posts : []
    }

    private var isEmpty: Bool {
        conversations.isEmpty && said.isEmpty && pictures.isEmpty && posts.isEmpty
    }

    private func conversationRow(_ hit: SearchResults.Conversation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: hit.isDirect ? "bubble.left" : "bubble.left.and.bubble.right")
                .foregroundStyle(palette.secondaryText)
                .frame(width: 22)
            Text(verbatim: hit.name)
                .foregroundStyle(palette.primaryText)
            Spacer(minLength: 0)
        }
    }

    private func saidRow(_ hit: SearchResults.Said) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(verbatim: hit.author.displayName)
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                Text(verbatim: hit.roomName)
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.tertiaryText)
                Spacer(minLength: 0)
                Text(hit.sentAt.formatted(date: .abbreviated, time: .omitted))
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.tertiaryText)
            }
            Text(verbatim: hit.body)
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(2)
        }
    }

    private func pictureRow(_ hit: SearchResults.Picture) -> some View {
        HStack(spacing: 12) {
            Image(systemName: hit.media.kind == .video ? "play.rectangle" : "photo")
                .foregroundStyle(palette.secondaryText)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: hit.caption.isEmpty ? hit.roomName : hit.caption)
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(verbatim: hit.author.displayName)
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private func postRow(_ post: OutpostPost) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: post.author.displayName)
                .font(CarpenterFont.rowTitle)
                .foregroundStyle(palette.primaryText)
            Text(verbatim: post.body)
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .lineLimit(2)
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                // COPY BEGIN 8f7294a4 [NEEDS HUMAN REVIEW]
                if !conversations.isEmpty {
                    Section {
                        ForEach(conversations) { hit in
                            Button { onOpenRoom(hit.room) } label: { conversationRow(hit) }
                        }
                    } header: {
                        Text("Conversations", bundle: .module).sectionHeading()
                    }
                    .groupedRowSurface()
                }
                // COPY END 8f7294a4

                // COPY BEGIN 45d87d54 [NEEDS HUMAN REVIEW]
                if !said.isEmpty {
                    Section {
                        ForEach(said) { hit in
                            Button { onOpenMessage(hit.room, hit.message) } label: { saidRow(hit) }
                        }
                    } header: {
                        Text("Messages", bundle: .module).sectionHeading()
                    }
                    .groupedRowSurface()
                }
                // COPY END 45d87d54

                // COPY BEGIN a5a425d7 [NEEDS HUMAN REVIEW]
                if !pictures.isEmpty {
                    Section {
                        ForEach(pictures) { hit in
                            Button { onOpenMessage(hit.room, hit.message) } label: { pictureRow(hit) }
                        }
                    } header: {
                        Text("Photos", bundle: .module).sectionHeading()
                    }
                    .groupedRowSurface()
                }
                // COPY END a5a425d7

                // COPY BEGIN 0ecce145 [NEEDS HUMAN REVIEW]
                if !posts.isEmpty {
                    Section {
                        ForEach(posts) { post in
                            Button { onOpenPost(post) } label: { postRow(post) }
                        }
                    } header: {
                        Text("Outposts", bundle: .module).sectionHeading()
                    }
                    .groupedRowSurface()
                }
                // COPY END 0ecce145
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            // COPY BEGIN 8ed7275f [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("Search", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                prompt: Text("Conversations, messages, photos and Outposts", bundle: .module))
            // COPY END 8ed7275f
            .autocorrectionDisabled()
            .searchFocused($searching)
            .onAppear { Task { searching = true } }
            .task(id: query) {
                let asked = trimmed
                guard !asked.isEmpty else {
                    results = SearchResults()
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                results = onSearch(asked)
            }
            .searchScopes($scope) {
                ForEach(Scope.allCases, id: \.self) { scope in
                    Text(scope.label, bundle: .module).tag(scope)
                }
            }
            .overlay {
                if isEmpty, !trimmed.isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                        .background(palette.background)
                } else if trimmed.isEmpty {
                    // COPY BEGIN 93a96e73 [NEEDS HUMAN REVIEW]
                    ContentUnavailableView {
                        Label {
                            Text("Search \(Branding.displayName)", bundle: .module)
                        } icon: {
                            Image(systemName: "magnifyingglass")
                        }
                    } description: {
                        Text(
                            "Conversations by name, what was said, photos by their caption or who sent them, and Outpost posts. A message you hid, one that was withdrawn, and anybody you blocked are never returned. Nothing leaves this device.",
                            bundle: .module)
                    }
                    .background(palette.background)
                    // COPY END 93a96e73
                }
            }
        }
    }
}
