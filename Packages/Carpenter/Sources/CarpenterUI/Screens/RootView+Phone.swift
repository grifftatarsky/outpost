import CarpenterKit
import CarpenterMedia
import SwiftUI

// MARK: The phone: five tabs and what You holds

extension RootView {
    private var youTabIcon: Image {
        let palette = Palette(
            accent: theme.accent,
            appearance: colorScheme == .dark ? .dark : .light,
            contrast: contrast)
        let renderer = ImageRenderer(
            content: AvatarView(initials: owner.initials, diameter: 26, isAccented: true, image: ownAvatar)
                .environment(\.palette, palette))
        renderer.scale = displayScale
        #if canImport(UIKit)
            if let image = renderer.uiImage {
                return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
            }
        #else
            if let image = renderer.nsImage {
                image.isTemplate = false
                return Image(nsImage: image)
            }
        #endif
        return Image(systemName: "person.crop.circle")
    }

    var visibleTab: Binding<PhoneTab> {
        Binding(
            get: { tab == .rooms && !isSplitInbox ? .messages : tab },
            set: { tab = $0 })
    }

    var phone: some View {
        TabView(selection: visibleTab) {
            Tab(value: PhoneTab.messages) {
                NavigationStack(path: roomPath) {
                    RoomsListView(
                        rooms: visibleRooms,
                        awaiting: awaitingAdmission,
                        managedTags: managedTags,
                        scope: isSplitInbox ? .direct : .everything,
                        preferences: preferences,
                        organisation: $organisation, syncedPeers: syncedPeers, cannotSend: cannotSend,
                        lastSync: lastSync, connections: connections, onCreateRoom: onCreateRoom,
                        onStartSolo: onStartSolo, showsPrivacyNote: showsPrivacyNote,
                        onJoinWithInvite: onRedeemInvite,
                        onAppearSync: onSync,
                        isSilenced: isSilenced,
                        onSilence: { room, silenced in Task { await onSilence(room, silenced) } },
                        onMarkRead: { room in Task { await onMarkRoomRead(room) } },
                        onLeave: { room in leaving = visibleRooms.first { $0.id == room } },
                        roomDeletion: roomDeletion,
                        onDelete: { room in deleting = visibleRooms.first { $0.id == room } },
                        focus: focusBinding,
                        preview: { previewMessages($0) }
                    )
                    .refreshable { await onSync() }
                    .navigationDestination(for: RoomID.self) { id in
                        roomDestination(id)
                    }
                    .navigationDestination(for: PersonRoute.self) { route in
                        personDestination(route)
                    }
                }
            } label: {
                Label {
                    if isSplitInbox {
                        Text("Solos", bundle: .module)
                    } else {
                        Text("Messages", bundle: .module)
                    }
                } icon: {
                    Image(systemName: "bubble.left")
                }
            }
            .badge(unreadCount(isSplitInbox ? .direct : .everything))

            if isSplitInbox {
                Tab(value: PhoneTab.rooms) {
                    NavigationStack(path: roomPath) {
                        RoomsListView(
                            rooms: visibleRooms,
                            // A split inbox used to hand `awaiting` to the Solos tab and not this
                            // one, so somebody waiting to be let into a room saw the invitation on
                            // the wrong tab and never on this one. An invitation that is invisible
                            // is worse than one shown twice, so both tabs get it until
                            // `AwaitingAdmission` can say which kind of room it is for.
                            awaiting: awaitingAdmission,
                            managedTags: managedTags,
                            scope: .groups,
                            preferences: preferences,
                        organisation: $organisation, syncedPeers: syncedPeers, cannotSend: cannotSend,
                            lastSync: lastSync, connections: connections,
                            onCreateRoom: onCreateRoom, onStartSolo: onStartSolo,
                            showsPrivacyNote: showsPrivacyNote,
                            onJoinWithInvite: onRedeemInvite,
                            onAppearSync: onSync,
                            isSilenced: isSilenced,
                            onSilence: { room, silenced in Task { await onSilence(room, silenced) } },
                            onMarkRead: { room in Task { await onMarkRoomRead(room) } },
                            onLeave: { room in leaving = visibleRooms.first { $0.id == room } },
                            roomDeletion: roomDeletion,
                            onDelete: { room in deleting = visibleRooms.first { $0.id == room } },
                            focus: focusBinding,
                            preview: { previewMessages($0) }
                        )
                        .refreshable { await onSync() }
                        .navigationDestination(for: RoomID.self) { id in
                            roomDestination(id)
                        }
                        .navigationDestination(for: PersonRoute.self) { route in
                            personDestination(route)
                        }
                    }
                } label: {
                    Label {
                        Text("Rooms", bundle: .module)
                    } icon: {
                        Image(systemName: "bubble.left.and.bubble.right")
                    }
                }
                .badge(unreadCount(.groups))
            }

            if outpostSettings.consent?.showsOutposts ?? true {
            Tab(value: PhoneTab.outposts) {
                NavigationStack(path: $outpostPath) {
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
                        showsAllOutposts: true,
                        onSeen: { await onMarkOutpostSeenPost($0) },
                        canJoinIn: canJoinIn
                    )
                    .onAppear { askingConsent = outpostSettings.consent == nil }
                    .sizedSheet(isPresented: $askingConsent) {
                        OutpostConsentSheet { answer in
                            askingConsent = false
                            await outpostSettings.onConsent(answer)
                        }
                    }
                    .navigationDestination(for: AllOutpostsRoute.self) { _ in
                        outpostList
                    }
                    .navigationDestination(for: OutpostPost.self) { post in
                        postDestination(post)
                    }
                    .navigationDestination(for: ParticipantID.self) { id in
                        outpostDestination(id)
                    }
                }
            } label: {
                Label {
                    Text("Outposts", bundle: .module)
                } icon: {
                    Image(systemName: "rectangle.stack")
                }
            }
            .badge(unseenOutpostCount)
            }

            Tab(value: PhoneTab.search, role: .search) {
                SearchTabView(
                    onSearch: onSearch,
                    onOpenRoom: { id in
                        tab = isSplitInbox && !(visibleRooms.first { $0.id == id }?.isDirect ?? true)
                            ? .rooms : .messages
                        roomPath.wrappedValue.append(id)
                    },
                    onOpenMessage: { room, _ in
                        tab = isSplitInbox && !(visibleRooms.first { $0.id == room }?.isDirect ?? true)
                            ? .rooms : .messages
                        roomPath.wrappedValue.append(room)
                    },
                    onOpenPost: { post in
                        tab = .outposts
                        outpostPath.append(post)
                    })
            }

            Tab(value: PhoneTab.you) {
                NavigationStack {
                    // One constructor for both platforms. There were two, with the same very
                    // long argument list, and they had already drifted: this one omitted
                    // `tutorialMode`, so *Help on every screen* wrote a preference that nothing
                    // on iPhone read — the exact defect its own ticket claimed to have fixed,
                    // fixed on the desktop path only. Found by walking the rig, 2026-09-15.
                    youScreen
                    .navigationDestination(for: ParticipantID.self) { id in
                        outpostDestination(id)
                    }
                    .navigationDestination(for: OutpostPost.self) { post in
                        postDestination(post)
                    }
                }
            } label: {
                Label {
                    Text("You", bundle: .module)
                } icon: {
                    youTabIcon
                }
            }
            .badge(youNeedsAttention ? Text(verbatim: "!") : nil)
        }
        .themed(theme.accent)
        .environment(\.showsAvatars, preferences.showsAvatars)
        .environment(\.blursSensitiveMedia, safety.blursSensitiveMedia)
        .environment(\.hapticsEnabled, theme.playsHaptics)
        .onChange(of: organisation) { _, updated in
            onOrganisationChange { $0 = updated }
        }
    }

    func moveRooms(from source: IndexSet, to destination: Int) {
        var order = rooms
        order.move(fromOffsets: source, toOffset: destination)

        guard let moved = source.first.map({ rooms[$0] }),
            let landing = order.firstIndex(where: { $0.id == moved.id })
        else { return }

        onOrganisationChange { organisation in
            organisation.movePin(
                moved.id,
                between: landing > 0 ? order[landing - 1].id : nil,
                and: landing < order.count - 1 ? order[landing + 1].id : nil,
                stamp: OrganisationStamp(at: roomClock.now, device: stampDevice))
        }
    }

    var youScreen: YouView {
        YouView(
            accent: $theme.accent,
            tutorialMode: $theme.tutorialMode,
            playsHaptics: $theme.playsHaptics,
            showsMessageDelay: $theme.showsMessageDelay,
            reportsDisplaying: Binding(
                get: { reportsDisplaying },
                set: { value in Task { await onReportsDisplayingChange(value) } }),
            notificationLevel: Binding(
                get: { notificationLevel },
                set: { value in Task { await onNotificationLevelChange(value) } }),
            debugActions: debugActions,
            demoConversation: $theme.demoConversation,
            demoParticipants: $theme.demoParticipants,
            demoOutpost: $theme.demoOutpost,
            outpostSettings: outpostSettings,
            inbox: Binding(get: { preferences.inbox }, set: { preferences.inbox = $0 }),
            showsAvatars: Binding(get: { preferences.showsAvatars }, set: { preferences.showsAvatars = $0 }),
            hiddenMessageCount: hiddenMessageCount,
            recoveryKey: recoveryKey,
            notifications: notifications,
            supporter: supporter,
            onRevealHidden: onRevealHidden,
            blursSensitiveMedia: $safety.blursSensitiveMedia,
            screening: screening,
            onOpenSystemSettings: onOpenSystemSettings,
            blocksKnownAbusers: $safety.blocksKnownAbusers,
            requiresSoloCheck: requiresSoloCheck,
            onRequiresSoloCheck: onRequiresSoloCheck,
            requiresLongPhrase: requiresLongPhrase,
            onRequiresLongPhrase: onRequiresLongPhrase,
            toldAboutRestores: toldAboutRestores,
            onToldAboutRestores: onToldAboutRestores,
            holdsHistoryForRestores: holdsHistoryForRestores,
            onHoldsHistoryForRestores: onHoldsHistoryForRestores,
            asksPeersForHistory: asksPeersForHistory,
            onAsksPeersForHistory: onAsksPeersForHistory,
            denyListUpdated: denyListUpdated,
            blockedPeople: blockedPeople,
            onUnblock: onUnblock,
            debugBlursEveryPhoto: $safety.blursEveryPhoto,
            onEraseEverything: onEraseEverything,
            onRename: onRenameMember,
            onAvatarChange: onAvatarChange,
            connections: connections, nickname: nickname, sharedName: sharedName,
            onNicknameChange: onNicknameChange, onPersonAvatarChange: onPersonAvatarChange,
            sharing: Binding(get: { sharing }, set: { value in Task { await onSharingChange(value) } }),
            focus: focusBinding,
            owner: owner,
            fingerprint: owner.id.groupedFingerprint,
            postCount: feed.count { $0.isMine },
            audiencePeople: audiencePeople,
            tagCount: organisation.orderedTags.count,
            identityCode: identityCode,
            integrity: integrity,
            mediaBytes: mediaBytes,
            appIcon: Binding(
                get: { icons.choice },
                set: { choice in
                    icons.choice = choice
                    Task { await onAppIconChange(choice) }
                }
            ),
            appIconIsSupported: appIconIsSupported,
            devices: devices,
            onRevokeDevice: onRevokeDevice,
            onRenameDevice: onRenameDevice
        )
    }
}
