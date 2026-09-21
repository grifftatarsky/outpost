import CarpenterKit
import CarpenterMedia
import SwiftUI

// MARK: The Outpost tab, and everything it pushes

extension RootView {
    var outpostList: some View {
        OutpostListView(
            people: visibleOutpostAuthors.filter { $0.id != owner.id },
            unseen: unseenOutposts,
            notified: notifiedOutposts,
            onMarkSeen: onMarkOutpostSeen,
            onSetNotified: onSetOutpostNotified)
    }

    var canJoinIn: Bool { outpostSettings.consent?.participates ?? true }

    @ViewBuilder func postDestination(_ post: OutpostPost) -> some View {
        PostThreadView(
            post: post,
            comments: DemoOutpost.isDemo(post)
                ? DemoOutpost.comments(for: post) : comments(post),
            viewer: owner.id,
            onComment: { await onComment(post, $0) },
            onReactToPost: { await onReact(post, $0) },
            onReactToComment: onReactToComment,
            canJoinIn: canJoinIn || post.isMine,
            hidden: DemoOutpost.isDemo(post) ? 0 : hiddenComments(post),
            settings: outpostSettings,
            postActions: postActions)
    }

    @ViewBuilder func personDestination(_ route: PersonRoute) -> some View {
        PersonDetailView(
            connection: connections.first { $0.id == route.person }
                ?? Connection(
                    person: messageActions.member(route.person) ?? .placeholder(route.person),
                    sharedRooms: 0, seesTheirOutpost: false),
            nickname: nickname(route.person),
            sharedName: sharedName(route.person),
            onNicknameChange: onNicknameChange,
            onPersonAvatarChange: onPersonAvatarChange)
    }

    @ViewBuilder func outpostDestination(_ id: ParticipantID) -> some View {
        OutpostView(
            owner: (visibleOutpostAuthors + [owner]).first { $0.id == id } ?? owner,
            posts: id == owner.id ? visibleFeed.filter(\.isMine) : visibleFeed.filter { $0.author.id == id },
            audiencePeople: audiencePeople,
            isViewer: id == owner.id,
            onPost: { await onSend($0, .ownOutpost) },
            onAttach: onAttachPost,
            postActions: postActions,
            audience: outpostAudience,
            reciprocal: id == owner.id ? nil : reciprocalAccess(id),
            onChangeAccess: onOutpostChoice,
            onSeen: id == owner.id ? nil : { await onMarkOutpostSeen(id) },
            blurb: outpostBlurb(id),
            settings: id == owner.id
                ? nil
                : OutpostDetailSettings(
                    person: (visibleOutpostAuthors + [owner]).first { $0.id == id } ?? owner,
                    isNotified: notifiedOutposts.contains(id),
                    acrossAllOutposts: notifications?.outposts.newPosts ?? .each,
                    onSetNotified: { on in await onSetOutpostNotified(id, on) }),
            onPerson: id == owner.id ? nil : { aboutPerson = $0 },
            onRefresh: onSync,
            onReact: { post, emoji in
                guard !DemoOutpost.isDemo(post) else { return }
                await onReact(post, emoji)
            },
            canJoinIn: canJoinIn,
            onPicture: id == owner.id ? outpostSettings.onWallPicture : nil)
        .navigationDestination(item: $aboutPerson) { about in
            OutpostPersonView(
                access: about,
                isNotified: notifiedOutposts.contains(about.person.id),
                isBlocked: blockedPeople.contains { $0.id == about.person.id },
                onChangeAccess: {
                    changingAccess = OutpostAccessSubject(
                        person: about.person, grant: about.youGave)
                },
                onSetNotified: { await onSetOutpostNotified(about.person.id, $0) },
                onBlock: { await onBlock(about.person.id) },
                onUnblock: { await onUnblock(about.person.id) })
        }
        .outpostAccessSheet(deciding: $changingAccess) { person, choice in
            await onOutpostChoice(person, choice, nil)
        }
    }

    var visibleFeed: [OutpostPost] {
        guard debugActions != nil, theme.demoOutpost else { return feed }
        return (DemoOutpost.posts() + feed).sorted { $0.postedAt > $1.postedAt }
    }

    var visibleOutpostAuthors: [Member] {
        let real = outpostAuthors.isEmpty ? [owner] : outpostAuthors
        guard debugActions != nil, theme.demoOutpost else { return real }
        return real + DemoOutpost.authors
    }
}
