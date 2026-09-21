import CarpenterKit
import CarpenterMedia
import SwiftUI

// MARK: The rooms list, and what opening one shows

extension RootView {
    var visibleRooms: [RoomSummary] {
        guard debugActions != nil, theme.demoConversation else { return rooms }
        return rooms + [
            DemoConversation.room(participants: theme.demoParticipants),
            DemoConversation.directRoom(),
        ]
    }

    @ViewBuilder
    private func demoConversationView(_ id: ConversationID) -> some View {
        if id == DemoConversation.directRoomID {
            ConversationView(
                room: DemoConversation.directRoom(),
                messages: DemoConversation.directMessages(),
                onSend: { _ in DemoConversation.refusal }
            )
        } else {
            ConversationView(
                room: DemoConversation.room(participants: theme.demoParticipants),
                messages: DemoConversation.messages(participants: theme.demoParticipants),
                onSend: { _ in DemoConversation.refusal }
            )
        }
    }

    private func actions(for room: ConversationID) -> MessageActions {
        var bound = messageActions
        bound.react = { message, emoji in await onReactToMessage(message, room, emoji) }
        return bound
    }

    private func hasAnInviteToShow(_ room: ConversationID) -> Bool {
        guard rooms.first(where: { $0.id == room })?.isDirect == true else { return false }
        return roomInvitations(room).contains { $0.isMine && !$0.hasConfirmed }
    }

    func offerComparison(in room: ConversationID) async {
        let people = comparisonToOffer(room)
        guard !people.isEmpty else { return }
        offeringComparison = ComparisonOffer(room: room, people: people)
        await onComparisonOffered(people.map(\.id))
    }

    func leaving(_ room: ConversationID) -> LeavingThisRoom? {
        guard roomStanding(room).mayWrite else { return nil }
        let leave = onLeaveRoom
        return LeavingThisRoom { await leave(room) }
    }

    func notGoneHelp(for id: ConversationID) -> NotGoneHelp {
        let showingWaiting = $showingWaiting
        let showWaiting: @MainActor @Sendable () -> Void = { showingWaiting.wrappedValue = id }
        guard roomNotGone != nil else {
            return NotGoneHelp(reason: cannotSend, onShowWaiting: showWaiting)
        }
        let notifying = $notifying
        return NotGoneHelp(
            reason: cannotSend, onChangeWait: { notifying.wrappedValue = id },
            onShowWaiting: showWaiting)
    }

    @ViewBuilder
    func roomDestination(_ id: ConversationID) -> some View {
        if isDemoRoom(id) {
            demoConversationView(id)
        } else if let room = rooms.first(where: { $0.id == id }) {
            ConversationView(
                room: room,
                transcript: conversation.isEmpty
                    ? transcript(id) : conversation.map(TranscriptEntry.message),
                pendingJoinCount: pendingJoins(id).count { !$0.isAlreadyIn },
                uncheckedCount: pendingJoins(id).count(where: \.isAlreadyIn),
                onSend: { await onSend($0, id) },
                onAttach: onAttach.map { attach in { picked, caption in await attach(picked, caption, id) } },
                onHide: onHideMessage,
                hiddenCount: hiddenInRoom(id),
                onRevealHidden: { await onRevealHiddenInRoom(id) },
                onSeen: { await onSeenMessage($0, id) },
                messageDelay: {
                    debugActions != nil && theme.showsMessageDelay ? messageDelay($0) : nil
                },
                onInvite: room.isDirect ? nil : { starting = id },
                onShowInvite: hasAnInviteToShow(id) ? { showingOutstanding = id } : nil,
                onReviewJoins: room.isDirect ? nil : { reviewing = id },
                onWhoYouAreTalkingTo: { checkingWho = id },
                soloCheck: soloCheck(id),
                onAskWhoYouAreTalkingTo: room.isDirect
                    ? { holding in await onAskWhoYouAreTalkingTo(id, holding) } : nil,
                onAnswerWhoYouAreTalkingTo: room.isDirect
                    ? { matched in await onAnswerWhoYouAreTalkingTo(id, matched) } : nil,
                onStopRequiringSoloCheck: room.isDirect && requiresSoloCheck
                    ? { await onRequiresSoloCheck(false) } : nil,
                soloPhrase: room.isDirect
                    ? whoYouAreTalkingTo(id).first { $0.id != viewer }?.phrase : nil,
                onRoomAccess: roomAccess(id) == nil || room.isDirect ? nil : { adjusting = id },
                onRoomNotifications: { notifying = id },
                onRoomMembers: room.isDirect ? nil : { viewingMembers = id },
                onActiveSync: onSync,
                standing: roomStanding(id),
                messageActions: actions(for: id),
                partnerFocus: room.partner.flatMap(focusStatus),
                repair: repairStatus(id),
                repairTargets: roomMembers(id).filter { $0.id != viewer },
                onRepair: roomStanding(id).mayWrite ? { await onRepair(id, $0) } : nil,
                onDismissRepair: { await onDismissRepair(id) },
                outpostReview: outpostReview(id),
                heldRestore: heldRestore(id),
                onLetHistoryThrough: onLetHistoryThrough,
                onRefuseHistory: onRefuseHistory,
                onOutpostChoice: onOutpostChoice,
                onPostponeReview: { await onPostponeReview(id) },
                onDelete: roomDeletion(id) == .allowed ? { deleting = room } : nil
            )
            .environment(\.notGoneHelp, notGoneHelp(for: id))
            .environment(\.leavingThisRoom, leaving(id))
            .sizedSheet(item: $greeting) { greeted in
                JoinPromptView(greeting: greeted) { await onGreetingSeen(greeted.id) }
                    .interactiveDismissDisabled()
            }
            .task(id: id) {
                greeting = roomGreeting(id)
                guard greeting == nil else { return }
                await offerComparison(in: id)
            }
            .onChange(of: greeting) { was, now in
                guard was?.id == id, now == nil else { return }
                Task { await offerComparison(in: id) }
            }
            .sizedSheet(item: $offeringComparison) { offer in
                ComparisonOfferView(offer: offer, onMarkChecked: onMarkChecked)
            }
            .sizedSheet(item: $viewingMembers) { room in
                NavigationStack {
                    RoomMembersView(
                        roomName: rooms.first { $0.id == room }?.name ?? "",
                        members: roomMembers(room),
                        invited: roomInvitations(room),
                        viewer: viewer,
                        onRemove: roomStanding(room).mayWrite
                            ? { await onRemoveMember(room, $0) } : nil,
                        onInvite: roomStanding(room).mayWrite
                            ? { viewingMembers = nil; starting = room } : nil,
                        onBlock: messageActions.block.map { block in { person in await block(person) } },
                        onRescind: roomStanding(room).mayWrite
                            ? { person in await onRescindInvitation(room, person) } : nil,
                        onDecide: roomStanding(room).mayWrite
                            ? { person, admit in
                                guard let join = pendingJoins(room).first(where: { $0.id == person })
                                else { return }
                                await onDecideJoin(room, join, admit)
                            } : nil
                    )
                    .navigationDestination(for: PersonRoute.self) { route in
                        personDestination(route)
                    }
                }
                .environment(\.leavingThisRoom, leaving(room))
            }
            .sizedSheet(item: $starting) { room in
                StartInviteView(
                    roomName: rooms.first { $0.id == room }?.name ?? "",
                    onIssue: { code, lifetime, sharesHistory in
                        guard let issued = await onInvite(room, code, lifetime, sharesHistory)
                        else {
                            return false
                        }
                        invite = PresentedInvite(
                            roomName: rooms.first { $0.id == room }?.name ?? "",
                            invite: issued)
                        return true
                    }
                )
            }
            .sizedSheet(item: $showingWaiting) { room in
                NavigationStack {
                    WaitingOnView(
                        roomName: rooms.first { $0.id == room }?.name ?? "",
                        people: waitingOn(room))
                }
            }
            .sizedSheet(item: $checkingWho) { room in
                NavigationStack {
                    WhoYouAreTalkingToView(
                        roomName: rooms.first { $0.id == room }?.name ?? "",
                        people: whoYouAreTalkingTo(room),
                        onMarkChecked: onMarkChecked)
                }
            }
            .sizedSheet(item: $showingOutstanding) { room in
                OutstandingInviteSheet(
                    roomName: rooms.first { $0.id == room }?.name ?? "",
                    load: { await onOutstandingInvite(room) })
            }
            .sizedSheet(item: $invite) { presented in
                InviteView(
                    roomName: presented.roomName,
                    invite: presented.invite,
                    phrase: phraseLookup(presented.invite),
                    notAskedYet: presented.notAskedYet
                )
            }
            .sizedSheet(item: $notifying) { room in
                NavigationStack {
                    NotificationLevelView(
                        level: Binding(
                            get: { roomNotificationLevel(room) },
                            set: { value in
                                Task { await onRoomNotificationLevelChange(room, value) }
                            }),
                        room: rooms.first { $0.id == room }?.name,
                        followingDefault: roomFollowsDefaultNotifications(room),
                        receipts: roomReceipts.map { $0(room) },
                        notGone: roomNotGone.map { $0(room) }
                    )
                }
            }
            .sizedSheet(item: $adjusting) { room in
                if let current = roomAccess(room) {
                    RoomAccessView(
                        roomName: rooms.first { $0.id == room }?.name ?? "",
                        members: roomMembers(room),
                        access: current,
                        onChange: { await onRoomAccessChange(room, $0) }
                    )
                }
            }
            .sizedSheet(item: $reviewing) { room in
                JoinRequestsView(
                    roomName: rooms.first { $0.id == room }?.name ?? "",
                    joins: { pendingJoins(room) },
                    onDecide: { join, admit in
                        await onDecideJoin(room, join, admit)
                    }
                )
            }
        }
    }

    func previewMessages(_ id: ConversationID) -> [Message] {
        if id == DemoConversation.directRoomID { return DemoConversation.directMessages() }
        if id == DemoConversation.roomID {
            return DemoConversation.messages(participants: theme.demoParticipants)
        }
        return messages(id)
    }

    private func isDemoRoom(_ id: ConversationID) -> Bool {
        id == DemoConversation.roomID || id == DemoConversation.directRoomID
    }

    var roomPath: Binding<[ConversationID]> {
        Binding(
            get: { openRoom.map { [$0] } ?? [] },
            set: { openRoom = $0.last })
    }
}
