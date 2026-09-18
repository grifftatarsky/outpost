import CarpenterKit
import SwiftUI

// MARK: The list itself, its filter and its empty state

extension RoomsListView {
    var content: some View {
        VStack(spacing: 0) {
            if searched.isEmpty && awaiting.isEmpty && query.isEmpty && filter == nil {
                emptyState
            } else {
            List {
                if let cannotSend {
                    Section {
                        Label {
                            Text(verbatim: cannotSend)
                                .font(CarpenterFont.footnote)
                                .foregroundStyle(palette.primaryText)
                        } icon: {
                            Image(systemName: "exclamationmark.icloud.fill")
                                .foregroundStyle(palette.destructive)
                        }
                        .padding(.vertical, 2)
                    } header: {
                        Text("Nothing is going out", bundle: .module).sectionHeading()
                    }
                    .groupedRowSurface()
                }

                if !awaiting.isEmpty && showsAwaiting {
                    Section {
                        ForEach(awaiting) { admission in
                            AwaitingRow(
                                admission: admission,
                                diameter: preferences.density == .compact
                                    ? CarpenterMetrics.compactRoomAvatar
                                    : CarpenterMetrics.roomAvatar)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text("Waiting to be let in", bundle: .module).sectionHeading()
                    }
                }
                ForEach(searched) { room in
                    NavigationLink(value: room.id) {
                        row(for: room)
                    }
                        .listRowInsets(
                            EdgeInsets(
                                top: CarpenterMetrics.conversationRowPadding,
                                leading: CarpenterMetrics.conversationGutter,
                                bottom: CarpenterMetrics.conversationRowPadding,
                                trailing: CarpenterMetrics.screenMargin)
                        )
                        .listRowBackground(selectionGround(room.id))
                        .listRowSeparator(
                            room.id == searched.first?.id ? .hidden : .automatic, edges: .top)
                        .accessibilityAddTraits(selectedRoom == room.id ? .isSelected : [])
                        .accessibilityLabel(
                            scope.marksGroups && !room.isDirect
                                ? Text("\(room.name), group", bundle: .module)
                                : Text(room.name))
                        .contextMenu {
                            roomActions(for: room)
                        } preview: {
                            // A context menu's preview is hosted outside this hierarchy, so custom
                            // environment values do not reach it and `\.palette` falls back to its
                            // default — which is dark. The theme is re-applied here from
                            // `\.colorScheme`, which is trait-backed and does propagate.
                            ConversationPreview(room: room, messages: preview(room.id))
                                .themed(palette.accent)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollBounceBehavior(.always)
            .overlay {
                if !query.isEmpty, searched.isEmpty, awaiting.isEmpty || !showsAwaiting {
                    ContentUnavailableView.search(text: query)
                        .background(palette.background)
                }
            }
            .accessibilityRotor(Text("Unread", bundle: .module)) {
                ForEach(arranged.filter(\.hasUnread)) { room in
                    AccessibilityRotorEntry(room.name, id: room.id)
                }
            }
            }
        }
        .background(palette.background)
        .navigationTitle(Text(scope.title))
        .helpButton()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            #if !os(macOS)
                ToolbarItem(placement: .principal) {
                    Text(scope.title).font(.headline)
                }
            #endif
            ToolbarItem(placement: .navigation) { composeButton }
            ToolbarItem(placement: .primaryAction) { listMenu }
        }
        .safeAreaInset(edge: .top, spacing: 0) { tagFilter }
        .syncStatus(syncLine)
        .task { await onAppearSync() }
        .sizedSheet(isPresented: $isEditing) {
            EditRoomsListView(
                rooms: rooms.filter(scope.includes), title: scope.title, organisation: $organisation,
                isSilenced: isSilenced, onSilence: onSilence,
                onLeave: onLeave.map { leave in
                    { room in
                        isEditing = false
                        leave(room)
                    }
                },
                roomDeletion: roomDeletion,
                onDelete: onDelete.map { delete in
                    { room in
                        isEditing = false
                        delete(room)
                    }
                })
        }
        .modifier(
            StartingConversations(
                namingRoom: $isNamingRoom, pickingSolo: $isStartingSolo, soloInvite: $soloInvite,
                preferences: preferences, connections: connections,
                onCreateRoom: onCreateRoom, onStartSolo: onStartSolo))
        .sizedSheet(isPresented: $isManagingTags) {
            ManageTagsView(organisation: $organisation, preferences: preferences)
        }
        .sizedSheet(item: $taggingRoom) { room in
            RoomTagsSheet(room: room, organisation: $organisation)
        }
        .sizedSheet(isPresented: $isWritingFocusMessage) {
            if let focus {
                FocusMessageSheet(focus: focus)
            }
        }
    }

    @ViewBuilder
    private var tagFilter: some View {
        if !organisation.orderedTags.isEmpty || !visibleManagedTags.isEmpty {
            Group {
                switch preferences.tagFilterStyle {
                case .chips:
                    TagFilterRail(
                        tags: organisation.orderedTags, managed: visibleManagedTags, selection: $filter)
                case .menu:
                    TagFilterMenu(
                        tags: organisation.orderedTags, managed: visibleManagedTags, selection: $filter)
                        .padding(.horizontal, CarpenterMetrics.screenMargin)
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func selectionGround(_ room: RoomID) -> some View {
        if selectedRoom == room {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.accentColor.opacity(0.16))
                .padding(.horizontal, 6)
        } else {
            Color.clear
        }
    }

    private func row(for room: RoomSummary) -> some View {
        RoomRow(
            room: room, organisation: organisation, density: preferences.density,
            marksGroups: scope.marksGroups, isSilenced: isSilenced(room.id),
            showsAvatar: preferences.showsAvatars,
            isAwaitingSomebody: visibleManagedTags.contains {
                $0.kind == .invited && $0.rooms.contains(room.id)
            })
    }

    func stamp() -> OrganisationStamp {
        OrganisationStamp(at: clock.now, device: stampDevice)
    }


    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text(scope.emptyTitle)
            } icon: {
                Image(systemName: "bubble.left")
            }
        } description: {
            Text(scope.emptyDescription)
        } actions: {
            VStack(spacing: 12) {
                switch scope {
                case .direct:
                    Button { isStartingSolo = true } label: {
                        Text("Send a Solo", bundle: .module).primaryAction()
                    }
                    .prominentActionButton()
                case .groups:
                    Button { isNamingRoom = true } label: {
                        Text("Make a room", bundle: .module).primaryAction()
                    }
                    .prominentActionButton()
                case .everything:
                    Button { isStartingSolo = true } label: {
                        Text("Send a Solo", bundle: .module).primaryAction()
                    }
                    .prominentActionButton()
                    Button { isNamingRoom = true } label: {
                        Text("Make a room", bundle: .module).primaryAction()
                    }
                    .quietActionButton()
                }

                if let onJoinWithInvite {
                    Button(action: onJoinWithInvite) {
                        Text("I have an invite", bundle: .module).primaryAction()
                    }
                    .quietActionButton()
                }
            }
            .frame(maxWidth: CarpenterMetrics.readableWidth)
            .padding(.top, 6)
        }
        .background(palette.background)
    }
}
