import CarpenterKit
import CarpenterMedia
import SwiftUI

// MARK: The wide layout: a sidebar, a list and what is open — the Mac, and an iPad at full width

enum WideArea: Hashable {
    case messages(InboxScope)
    case outposts
    case search
    case you

    var stored: String {
        switch self {
        case .messages(.direct): "solos"
        case .messages(.groups): "rooms"
        case .messages(.everything): "messages"
        case .outposts: "outposts"
        case .search: "search"
        case .you: "you"
        }
    }

    init?(stored: String) {
        switch stored {
        case "solos": self = .messages(.direct)
        case "rooms": self = .messages(.groups)
        case "messages": self = .messages(.everything)
        case "outposts": self = .outposts
        case "search": self = .search
        case "you": self = .you
        default: return nil
        }
    }

    static func home(splitInbox: Bool) -> WideArea {
        splitInbox ? .messages(.groups) : .messages(.everything)
    }

    static func holding(isDirect: Bool, splitInbox: Bool) -> WideArea {
        guard splitInbox else { return .messages(.everything) }
        return .messages(isDirect ? .direct : .groups)
    }

    func normalised(splitInbox: Bool, showsOutposts: Bool) -> WideArea {
        switch self {
        case .messages(let scope):
            guard splitInbox else { return .messages(.everything) }
            return scope == .everything ? .messages(.groups) : self
        case .outposts:
            return showsOutposts ? self : .home(splitInbox: splitInbox)
        case .search, .you:
            return self
        }
    }
}

extension RootView {
    var showsOutposts: Bool { outpostSettings.consent?.showsOutposts ?? true }

    var defaultArea: WideArea { .home(splitInbox: isSplitInbox) }

    var currentArea: WideArea {
        (area ?? defaultArea).normalised(splitInbox: isSplitInbox, showsOutposts: showsOutposts)
    }

    func area(of room: RoomID) -> WideArea {
        .holding(
            isDirect: visibleRooms.first { $0.id == room }?.isDirect ?? false,
            splitInbox: isSplitInbox)
    }

    func go(_ place: Destination) {
        switch place {
        case .room(let id):
            area = area(of: id)
            openRoom = id
        case .allOutposts, .outpost:
            area = .outposts
            destination = place
            outpostPath = NavigationPath()
        case .you:
            area = .you
        }
    }

    var wide: some View {
        NavigationSplitView(columnVisibility: $wideColumns) {
            wideSidebar
        } content: {
            wideContent
        } detail: {
            wideDetail
        }
        #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    WaitingButton(
                        rooms: visibleRooms,
                        authors: waitingAuthors,
                        badge: waitingBadge,
                        onOpenRoom: { go(.room($0)) },
                        onOpenOutpost: { go(.outpost($0)) })
                }
            }
        #endif
        .onAppear { if area == nil { area = WideArea(stored: storedArea) ?? defaultArea } }
        .onChange(of: area) { _, picked in
            if let picked { storedArea = picked.stored }
        }
        #if os(iOS)
            .onGeometryChange(for: Bool.self) { $0.size.width < $0.size.height } action: { upright in
                isUpright = upright
                wideColumns = upright ? .doubleColumn : .all
                if upright { showsAudienceRail = false }
            }
            .onChange(of: area) { _, _ in
                if isUpright { wideColumns = .doubleColumn }
            }
        #endif
        .modifier(
            StartingConversations(
                namingRoom: $namingRoom, pickingSolo: $pickingSolo, soloInvite: $soloInvite,
                preferences: preferences, connections: connections,
                onCreateRoom: onCreateRoom, onStartSolo: onStartSolo))
        .focusedSceneValue(\.desktopActions, desktopActions)
        .themed(theme.accent)
        .environment(\.showsAvatars, preferences.showsAvatars)
        .environment(\.blursSensitiveMedia, safety.blursSensitiveMedia)
        .environment(\.hapticsEnabled, theme.playsHaptics)
        .onChange(of: organisation) { _, updated in
            onOrganisationChange { $0 = updated }
        }
    }

    var wideSidebar: some View {
        List(selection: Binding(get: { currentArea }, set: { if let picked = $0 { area = picked } })) {
            Section {
                if isSplitInbox {
                    NavigationLink(value: WideArea.messages(.direct)) {
                        Label {
                            Text("Solos", bundle: .module)
                        } icon: {
                            Image(systemName: "bubble.left")
                        }
                    }
                    .badge(unreadCount(.direct))
                    NavigationLink(value: WideArea.messages(.groups)) {
                        Label {
                            Text("Rooms", bundle: .module)
                        } icon: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                    }
                    .badge(unreadCount(.groups))
                } else {
                    NavigationLink(value: WideArea.messages(.everything)) {
                        Label {
                            Text("Messages", bundle: .module)
                        } icon: {
                            Image(systemName: "bubble.left")
                        }
                    }
                    .badge(unreadCount(.everything))
                }
                if showsOutposts {
                    NavigationLink(value: WideArea.outposts) {
                        Label {
                            Text("Outposts", bundle: .module)
                        } icon: {
                            Image(systemName: "rectangle.stack")
                        }
                    }
                    .badge(unseenOutpostCount)
                }
                NavigationLink(value: WideArea.search) {
                    Label {
                        Text("Search", bundle: .module)
                    } icon: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            Section {
                NavigationLink(value: WideArea.you) {
                    Label {
                        Text("You", bundle: .module)
                    } icon: {
                        Image(systemName: "person.crop.circle")
                    }
                }
                .badge(youNeedsAttention ? Text(verbatim: "!") : nil)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: sidebarWidth, max: max(260, sidebarWidth))
    }

    @ViewBuilder
    var wideContent: some View {
        switch currentArea {
        case .messages(let scope):
            NavigationStack(
                path: Binding(get: { [RoomID]() }, set: { if let id = $0.last { openRoom = id } })
            ) {
                roomsList(scope)
                    .refreshable { await onSync() }
                    .navigationDestination(for: RoomID.self) { _ in EmptyView() }
            }
            .environment(\.selectedRoom, openRoom)
            .navigationSplitViewColumnWidth(min: 300, ideal: listWidth, max: max(460, listWidth))

        case .outposts:
            outpostsColumn
                .navigationSplitViewColumnWidth(min: 260, ideal: listWidth * 0.85, max: max(400, listWidth))

        case .search:
            SearchTabView(
                onSearch: onSearch,
                onOpenRoom: { go(.room($0)) },
                onOpenMessage: { room, _ in go(.room(room)) },
                onOpenPost: { post in
                    go(.outpost(post.author.id))
                    outpostPath.append(post)
                })
            .navigationSplitViewColumnWidth(min: 300, ideal: listWidth, max: max(460, listWidth))

        case .you:
            youScreen
                .navigationDestination(for: ParticipantID.self) { id in
                    outpostDestination(id)
                }
                .navigationDestination(for: OutpostPost.self) { post in
                    postDestination(post)
                }
                .navigationSplitViewColumnWidth(min: 320, ideal: listWidth * 1.1, max: max(480, listWidth * 1.2))
        }
    }

    var outpostsColumn: some View {
        List(selection: $destination) {
            NavigationLink(value: Destination.allOutposts) {
                Label {
                    Text("All Outposts", bundle: .module)
                } icon: {
                    Image(systemName: "square.stack")
                }
            }
            Section {
                ForEach(outpostAuthors.isEmpty ? [owner] : outpostAuthors) { author in
                    NavigationLink(value: Destination.outpost(author.id)) {
                        HStack(spacing: 10) {
                            PersonAvatarView(member: author, diameter: 28, onOutpost: true)
                            Text(author.id == owner.id ? String(localized: "Your Outpost", bundle: .module) : author.displayName)
                                .fontWeight(unseenOutposts.contains(author.id) ? .semibold : .regular)
                            Spacer(minLength: 4)
                            if unseenOutposts.contains(author.id) {
                                Circle()
                                    .fill(.tint)
                                    .frame(width: 8, height: 8)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityValue(
                        unseenOutposts.contains(author.id) ? Text("Something new", bundle: .module) : Text(verbatim: ""))
                    .contextMenu {
                        if author.id != owner.id {
                            OutpostPersonActions.markRead(
                                author.id, isUnseen: unseenOutposts.contains(author.id), onMarkOutpostSeen)
                            OutpostPersonActions.notify(
                                author.id, isNotified: notifiedOutposts.contains(author.id), onSetOutpostNotified)
                        }
                    }
                }
            } header: {
                Text("People", bundle: .module).sectionHeading()
            }
        }
        .navigationTitle(Text("Outposts", bundle: .module))
    }

    @ViewBuilder
    var wideDetail: some View {
        switch currentArea {
        case .messages, .search:
            NavigationStack {
                if let openRoom {
                    roomDestination(openRoom)
                        .navigationDestination(for: PersonRoute.self) { route in
                            personDestination(route)
                        }
                } else {
                    ContentUnavailableView {
                        Label {
                            Text("No conversation open", bundle: .module)
                        } icon: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                    } description: {
                        Text("Choose one from the list, or start a new one.", bundle: .module)
                    }
                }
            }
            .id(openRoom)

        case .outposts:
            NavigationStack(path: $outpostPath) {
                outpostsDetail
                    .navigationDestination(for: AllOutpostsRoute.self) { _ in
                        outpostList
                    }
                    .navigationDestination(for: ParticipantID.self) { id in
                        outpostDestination(id)
                    }
                    .navigationDestination(for: OutpostPost.self) { post in
                        postDestination(post)
                    }
            }

        case .you:
            NavigationStack {
                ContentUnavailableView {
                    Label {
                        Text("You", bundle: .module)
                    } icon: {
                        Image(systemName: "person.crop.circle")
                    }
                } description: {
                    Text("Choose a page from the list.", bundle: .module)
                }
            }
        }
    }

    @ViewBuilder
    var outpostsDetail: some View {
        switch destination {
        case .outpost(let id) where id == owner.id:
            outpostDestination(id)
                .inspector(isPresented: $showsAudienceRail) { audienceRail }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showsAudienceRail.toggle() } label: {
                            Label {
                                Text("Who sees it", bundle: .module)
                            } icon: {
                                Image(systemName: "sidebar.trailing")
                            }
                        }
                    }
                }
        case .outpost(let id):
            outpostDestination(id)
        default:
            OutpostFeedView(
                viewer: owner,
                authors: visibleOutpostAuthors,
                posts: visibleFeed,
                onReact: { post, emoji in
                    guard !DemoOutpost.isDemo(post) else { return }
                    await onReact(post, emoji)
                },
                onPost: { await onSend($0, nil) },
                onAttach: onAttachPost,
                postActions: postActions,
                unseen: unseenOutposts,
                showsAllOutposts: false,
                onSeen: { await onMarkOutpostSeenPost($0) },
                canJoinIn: canJoinIn
            )
            .environment(\.showsPeopleRail, false)
            .onAppear { askingConsent = outpostSettings.consent == nil }
            .sizedSheet(isPresented: $askingConsent) {
                OutpostConsentSheet { answer in
                    askingConsent = false
                    await outpostSettings.onConsent(answer)
                }
            }
        }
    }

    var wideAreas: [DesktopActions.Area] {
        var areas: [DesktopActions.Area] =
            isSplitInbox
            ? [.init(area: .messages(.direct), title: .module("Solos")),
               .init(area: .messages(.groups), title: .module("Rooms"))]
            : [.init(area: .messages(.everything), title: .module("Messages"))]
        if showsOutposts { areas.append(.init(area: .outposts, title: .module("Outposts"))) }
        areas.append(.init(area: .search, title: .module("Search")))
        areas.append(.init(area: .you, title: .module("You")))
        return areas
    }

    var openRoomActions: DesktopActions.OpenRoom? {
        guard case .messages = currentArea, let id = openRoom,
            let room = visibleRooms.first(where: { $0.id == id })
        else { return nil }
        return DesktopActions.OpenRoom(
            name: room.name,
            hasUnread: room.hasUnread,
            isPinned: organisation.isPinned(id),
            isSilenced: isSilenced(id),
            deletion: roomDeletion(id),
            markRead: { Task { await onMarkRoomRead(id) } },
            setPinned: { pinned in
                organisation.setPinned(
                    pinned, for: id, stamp: OrganisationStamp(at: roomClock.now, device: stampDevice))
            },
            setSilenced: { silenced in Task { await onSilence(id, silenced) } },
            leave: { leaving = room },
            delete: { deleting = room })
    }

    var desktopActions: DesktopActions {
        DesktopActions(
            newRoom: { namingRoom = true },
            newSolo: { pickingSolo = true },
            joinWithInvite: onRedeemInvite,
            audienceShown: currentArea == .outposts && destination == .outpost(owner.id)
                ? showsAudienceRail : nil,
            toggleAudience: { showsAudienceRail.toggle() },
            areas: wideAreas,
            current: currentArea,
            show: { area = $0 },
            rooms: visibleRooms.map { ($0.id, $0.name) },
            openRoom: openRoomActions,
            go: { go($0) })
    }

    var settingsWindow: some View {
        youScreen
            .presentedAsSettings()
            .themed(theme.accent)
            .environment(\.showsAvatars, preferences.showsAvatars)
            .environment(\.blursSensitiveMedia, safety.blursSensitiveMedia)
            .environment(\.hapticsEnabled, theme.playsHaptics)
    }

    var audienceRail: some View {
        NavigationStack {
            OutpostAudienceView(outpostAudience)
        }
        .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
    }

    var waitingAuthors: [Member] {
        visibleOutpostAuthors.filter { unseenOutposts.contains($0.id) }
    }

    var waitingBadge: Int {
        guard let notifications, notifications.systemShowsBadges == true else { return 0 }
        return BadgeCount.of(
            visibleRooms, outposts: waitingAuthors.count, choices: notifications.badges)
    }
}
