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
                    // COPY BEGIN 1af10146 [NEEDS HUMAN REVIEW]
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
                    // COPY END 1af10146
                }

                // COPY BEGIN f347ac4e [NEEDS HUMAN REVIEW]
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
                // COPY END f347ac4e
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
                        .listRowBackground(Color.clear)
                        .listRowSeparator(
                            room.id == searched.first?.id ? .hidden : .automatic, edges: .top)
                        // COPY BEGIN f1ac657c [NEEDS HUMAN REVIEW]
                        .accessibilityLabel(
                            scope.marksGroups && !room.isDirect
                                ? Text("\(room.name), group", bundle: .module)
                                : Text(room.name))
                        // COPY END f1ac657c
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
            // COPY BEGIN 80c75a0f [NEEDS HUMAN REVIEW]
            .accessibilityRotor(Text("Unread", bundle: .module)) {
                ForEach(arranged.filter(\.hasUnread)) { room in
                    AccessibilityRotorEntry(room.name, id: room.id)
                }
            }
            // COPY END 80c75a0f
            }
        }
        .background(palette.background)
        .navigationTitle(Text(scope.title))
        .helpButton()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(scope.title).font(.headline)
            }
            ToolbarItem(placement: .navigation) { composeButton }
            ToolbarItem(placement: .primaryAction) { listMenu }
        }
        .safeAreaInset(edge: .top, spacing: 0) { tagFilter }
        .syncStatus(syncLine)
        .task { await onAppearSync() }
        .sheet(isPresented: $isEditing) {
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
        .sheet(isPresented: $isNamingRoom) {
            NewRoomView(preferences: preferences, connections: connections) { name, access, people in
                await onCreateRoom(name, access, people)
            }
        }
        .sheet(isPresented: $isStartingSolo) {
            SoloPickerView(connections: connections) { person in
                if let invite = await onStartSolo(person.id) {
                    soloInvite = PresentedInvite(
                        roomName: person.displayName, invite: invite, notAskedYet: true)
                }
            }
        }
        .sheet(item: $soloInvite) { presented in
            InviteView(
                roomName: presented.roomName, invite: presented.invite,
                phrase: phraseLookup(presented.invite),
                notAskedYet: presented.notAskedYet)
        }
        .sheet(isPresented: $isManagingTags) {
            ManageTagsView(organisation: $organisation, preferences: preferences)
        }
        .sheet(item: $taggingRoom) { room in
            RoomTagsSheet(room: room, organisation: $organisation)
        }
        .sheet(isPresented: $isWritingFocusMessage) {
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
                    // COPY BEGIN 0a3d7d2f [NEEDS HUMAN REVIEW]
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
                    // COPY END 0a3d7d2f
                }

                // COPY BEGIN 565b7d46 [NEEDS HUMAN REVIEW]
                if let onJoinWithInvite {
                    Button(action: onJoinWithInvite) {
                        Text("I have an invite", bundle: .module).primaryAction()
                    }
                    .quietActionButton()
                }
                // COPY END 565b7d46
            }
            .frame(maxWidth: CarpenterMetrics.readableWidth)
            .padding(.top, 6)
        }
        .background(palette.background)
    }
}
