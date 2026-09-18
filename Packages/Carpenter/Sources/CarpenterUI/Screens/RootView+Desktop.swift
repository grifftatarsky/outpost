import CarpenterKit
import CarpenterMedia
import SwiftUI

// MARK: The desktop: a sidebar instead of tabs

extension RootView {
    var desktop: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section(isExpanded: $outpostsExpanded) {
                    NavigationLink(value: Destination.allOutposts) {
                        Label {
                            Text("All Outposts", bundle: .module)
                        } icon: {
                            Image(systemName: "square.stack")
                        }
                    }

                    ForEach(outpostAuthors.isEmpty ? [owner] : outpostAuthors) { author in
                        NavigationLink(value: Destination.outpost(author.id)) {
                            HStack(spacing: 8) {
                                PersonAvatarView(member: author, diameter: 22, onOutpost: true)
                                Text(author.id == owner.id ? String(localized: "Your Outpost", bundle: .module) : author.displayName)
                            }
                        }
                    }
                } header: {
                    Text("Outposts", bundle: .module)
                        .badge(outpostAuthors.count)
                }

                Section(isExpanded: $roomsExpanded) {
                    ForEach(visibleRooms) { room in
                        NavigationLink(value: Destination.room(room.id)) {
                            Label {
                                Text(room.name)
                            } icon: {
                                Image(systemName: "bubble.left")
                            }
                        }
                    }
                    .onMove(perform: moveRooms)
                } header: {
                    Text("Rooms", bundle: .module)
                        .badge(rooms.count)
                }

                Section {
                    NavigationLink(value: Destination.you) {
                        Label {
                            Text("You", bundle: .module)
                        } icon: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 264, max: 320)
            .onChange(of: openRoom) { _, room in
                guard let room, destination != .room(room) else { return }
                destination = .room(room)
            }
            .onChange(of: destination) { _, picked in
                if case .room(let id) = picked { openRoom = id } else { openRoom = nil }
            }
        } detail: {
            NavigationStack {
                switch destination {
                case .room(let id):
                    roomDestination(id)
                        .navigationDestination(for: PersonRoute.self) { route in
                            personDestination(route)
                        }

                case .outpost(let id):
                    if id == owner.id {
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
                                    .keyboardShortcut("i", modifiers: [.command, .option])
                                }
                            }
                    } else {
                        outpostDestination(id)
                    }

                case .you:
                    youScreen

                case .allOutposts, .none:
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
                    .sheet(isPresented: $askingConsent) {
                        OutpostConsentSheet { answer in
                            askingConsent = false
                            await outpostSettings.onConsent(answer)
                        }
                    }
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
            }
        }
        .themed(theme.accent)
        .environment(\.showsAvatars, preferences.showsAvatars)
        .environment(\.blursSensitiveMedia, safety.blursSensitiveMedia)
        .environment(\.hapticsEnabled, theme.playsHaptics)
        .onChange(of: organisation) { _, updated in
            onOrganisationChange { $0 = updated }
        }
    }

    var audienceRail: some View {
        NavigationStack {
            OutpostAudienceView(outpostAudience)
        }
        .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
    }
}
