import CarpenterKit
import SwiftUI

extension EnvironmentValues {
    @Entry var selectedRoom: RoomID?
}

public struct RoomsListView: View {
    @Environment(\.palette) var palette
    @Environment(\.selectedRoom) var selectedRoom
    @Environment(\.clock) var clock
    @Environment(\.stampDevice) var stampDevice

    @Binding var organisation: RoomsListOrganisation
    let preferences: RoomsListPreferences
    @State var filter: TagID?
    @State var isEditing = false
    @State var isManagingTags = false
    @State var taggingRoom: RoomSummary?
    @State var isWritingFocusMessage = false

    let rooms: [RoomSummary]
    let syncedPeers: [String]
    let cannotSend: String?
    let lastSync: Date
    let onCreateRoom: (String, RoomAccess, Set<ParticipantID>) async -> Void
    let onStartSolo: (ParticipantID) async -> Invite?
    let showsPrivacyNote: Bool
    let connections: [Connection]
    let onJoinWithInvite: (() -> Void)?
    let onAppearSync: () async -> Void
    let isSilenced: (RoomID) -> Bool
    let onSilence: (RoomID, Bool) -> Void
    let onMarkRead: (RoomID) -> Void
    let onLeave: ((RoomID) -> Void)?
    let roomDeletion: (RoomID) -> RoomDeletion
    let onDelete: ((RoomID) -> Void)?
    let focus: Binding<FocusSharing>?
    let preview: (RoomID) -> [Message]
    let managedTags: [ManagedTag]
    let awaiting: [AwaitingAdmission]

    @State var isNamingRoom = false

    @State var isStartingSolo = false
    @State var soloInvite: PresentedInvite?
    @State var query = ""

    let scope: InboxScope

    public init(
        rooms: [RoomSummary],
        awaiting: [AwaitingAdmission] = [],
        managedTags: [ManagedTag] = [],
        scope: InboxScope = .everything,
        preferences: RoomsListPreferences = RoomsListPreferences(),
        organisation: Binding<RoomsListOrganisation>,
        syncedPeers: [String],
        cannotSend: String? = nil,
        lastSync: Date,
        connections: [Connection] = [],
        onCreateRoom: @escaping (String, RoomAccess, Set<ParticipantID>) async -> Void = { _, _, _ in },
        onStartSolo: @escaping (ParticipantID) async -> Invite? = { _ in nil },
        showsPrivacyNote: Bool = false,
        onJoinWithInvite: (() -> Void)? = nil,
        onAppearSync: @escaping () async -> Void = {},
        isSilenced: @escaping (RoomID) -> Bool = { _ in false },
        onSilence: @escaping (RoomID, Bool) -> Void = { _, _ in },
        onMarkRead: @escaping (RoomID) -> Void = { _ in },
        onLeave: ((RoomID) -> Void)? = nil,
        roomDeletion: @escaping (RoomID) -> RoomDeletion = { _ in .stillIn },
        onDelete: ((RoomID) -> Void)? = nil,
        focus: Binding<FocusSharing>? = nil,
        preview: @escaping (RoomID) -> [Message] = { _ in [] }
    ) {
        self.focus = focus
        self.rooms = rooms
        self.awaiting = awaiting
        self.managedTags = managedTags
        self.scope = scope
        self.preferences = preferences
        _organisation = organisation
        self.syncedPeers = syncedPeers
        self.cannotSend = cannotSend
        self.lastSync = lastSync
        self.connections = connections
        self.onCreateRoom = onCreateRoom
        self.onStartSolo = onStartSolo
        self.showsPrivacyNote = showsPrivacyNote
        self.onJoinWithInvite = onJoinWithInvite
        self.onAppearSync = onAppearSync
        self.isSilenced = isSilenced
        self.onSilence = onSilence
        self.onMarkRead = onMarkRead
        self.onLeave = onLeave
        self.roomDeletion = roomDeletion
        self.onDelete = onDelete
        self.preview = preview
    }

    var arranged: [RoomSummary] {
        organisation.arrange(
            rooms.filter(scope.includes), filteredBy: filter, managed: visibleManagedTags)
    }

    var searched: [RoomSummary] {
        guard !query.isEmpty else { return arranged }
        return arranged.filter { room in
            room.name.localizedStandardContains(query)
                || room.lastMessage.localizedStandardContains(query)
                || room.lastAuthor?.displayName.localizedStandardContains(query) == true
        }
    }

    var visibleManagedTags: [ManagedTag] {
        let mine = Set(rooms.filter(scope.includes).map(\.id))
            .union(showsAwaitingSection ? awaiting.map(\.room) : [])
        return managedTags.compactMap { tag in
            let named = tag.rooms.intersection(mine)
            guard !named.isEmpty else { return nil }
            return ManagedTag(kind: tag.kind, rooms: named)
        }
    }

    var showsAwaitingSection: Bool { !awaiting.isEmpty }

    var showsAwaiting: Bool {
        guard let filter else { return true }
        return visibleManagedTags.contains { $0.kind == .invited && $0.id == filter }
    }

    var syncLine: String? {
        if let filter, let tag = organisation.tags[filter] {
            return TagFilterSummary.line(
                matching: arranged.count, of: rooms.count, tagName: tag.name.value)
        }
        if let filter, visibleManagedTags.contains(where: { $0.id == filter }) {
            return TagFilterSummary.managedLine(
                matching: arranged.count + (showsAwaiting ? awaiting.count : 0))
        }
        return SyncSummary().caughtUpLine(
            peers: syncedPeers, knowsAnyone: SyncSummary.hasAnyoneToReach(in: rooms),
            at: lastSync, now: clock.now)
    }

    public var body: some View {
        content
            .safeAreaInset(edge: .bottom) {
                if showsPrivacyNote {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.accentColor)
                        Text("Privacy set. Change it any time under You › Privacy & Safety.", bundle: .module)
                    }
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CarpenterMetrics.screenMargin)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)  // cross-fade only
                }
            }
            .animation(.default, value: showsPrivacyNote)  // cross-fade only
    }
}
