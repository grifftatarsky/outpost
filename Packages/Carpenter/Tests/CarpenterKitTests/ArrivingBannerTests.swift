import CarpenterApp
import CarpenterKit
import Foundation
import Testing

@Suite("What the extension decides a banner is")
struct ArrivingBannerTests {
    private let room = RoomID()
    private let other = RoomID()
    private let alice = ParticipantID(rawValue: Data([0xA1]))

    private func message(_ seed: UInt8 = 1, in room: RoomID? = nil) -> IncomingMessage {
        IncomingMessage(
            id: MessageID(entry: EntryHash(rawValue: Data(repeating: seed, count: 32))),
            room: room ?? self.room, roomName: "Hangar 7", author: "Alice",
            body: "are you coming", sentAt: Date(timeIntervalSince1970: 1_000))
    }

    private func post(_ seed: UInt8 = 2) -> IncomingPost {
        IncomingPost(
            id: PostID(entry: EntryHash(rawValue: Data(repeating: seed, count: 32))),
            author: alice, authorName: "Alice", body: "the mooring mast drawings are 1:200",
            postedAt: Date(timeIntervalSince1970: 2_000))
    }

    private func ask(_ seed: UInt8 = 3) -> RestoreAsk {
        RestoreAsk(
            request: RepairID(rawValue: UUID()), person: alice, personName: "Alice",
            room: room, roomName: "Hangar 7")
    }

    private func world(
        filter: FocusFilter = FocusFilter(),
        level: NotificationLevel = .everything,
        perRoom: NotificationLevel? = nil
    ) -> WhatArrived.Surroundings {
        let forRoom = perRoom ?? level
        return WhatArrived.Surroundings(
            filter: filter, defaultLevel: level,
            levelForRoom: { _ in forRoom },
            isDirect: { _ in false },
            authorOfMessage: { _, _ in Member(id: self.alice, displayName: "Alice") })
    }

    private var nothingSeenYet: BannerSnapshot { BannerSnapshot(post: nil, ask: nil, message: nil) }

    // MARK: Whether anything arrived at all

    @Test("Nothing new means no banner")
    func nothingNewIsSilent() {
        let seen = BannerSnapshot(post: post().id, ask: ask().request, message: message().id)
        let banner = WhatArrived.since(
            seen, post: post(), ask: nil, message: message(), in: world())
        #expect(banner == nil, "a banner was drawn for something the device already had")
    }

    @Test("An empty device with nothing waiting says nothing")
    func emptyIsSilent() {
        #expect(
            WhatArrived.since(nothingSeenYet, post: nil, ask: nil, message: nil, in: world())
                == nil)
    }

    @Test("A message that is new only because an older one was the newest before")
    func aNewerMessageIsAnnounced() {
        let seen = BannerSnapshot(post: nil, ask: nil, message: message(1).id)
        let banner = WhatArrived.since(
            seen, post: nil, ask: nil, message: message(9), in: world())
        #expect(banner?.copy.body == "are you coming")
    }

    @Test("A message's banner names its room, so Reply and Mark as Read know where they go")
    func aMessageNamesItsRoom() {
        let banner = WhatArrived.since(
            nothingSeenYet, post: nil, ask: nil, message: message(in: other), in: world())
        #expect(banner?.room == other)
    }

    @Test("A post or a restore ask names no room, so it offers no answer")
    func onlyAMessageNamesARoom() {
        let fromAPost = WhatArrived.since(
            nothingSeenYet, post: post(), ask: nil, message: nil, in: world())
        let fromAnAsk = WhatArrived.since(
            nothingSeenYet, post: nil, ask: ask(), message: nil, in: world())
        #expect(fromAPost != nil && fromAPost?.room == nil)
        #expect(fromAnAsk != nil && fromAnAsk?.room == nil)
    }

    // MARK: Which one wins when two arrive in the same round

    @Test("A post is announced ahead of a message")
    func postBeatsMessage() {
        let banner = WhatArrived.since(
            nothingSeenYet, post: post(), ask: nil, message: message(), in: world())
        #expect(banner?.copy.title == "Alice")
        #expect(banner?.copy.subtitle == "Posted to their Outpost")
    }

    @Test("A restore ask is announced ahead of a message and behind a post")
    func askSitsBetween() {
        let both = WhatArrived.since(
            nothingSeenYet, post: post(), ask: ask(), message: message(), in: world())
        #expect(both?.sender?.isAboutAPost == true, "the post did not win")

        let withoutPost = WhatArrived.since(
            nothingSeenYet, post: nil, ask: ask(), message: message(), in: world())
        #expect(withoutPost?.copy != MessageNotification.generic)
        #expect(withoutPost?.copy.body != "are you coming", "the message won over the restore ask")
    }

    // MARK: Where a message's rung comes from

    @Test("A message takes its own room's rung, not the default")
    func theRoomsOwnRungIsUsed() {
        let banner = WhatArrived.since(
            nothingSeenYet, post: nil, ask: nil, message: message(),
            in: world(level: .everything, perRoom: .whereOnly))
        #expect(banner?.copy.title == "Hangar 7")
        #expect(banner?.copy.subtitle.isEmpty == true)
        #expect(banner?.copy.body.isEmpty == true, "a room set to name nobody put the words on screen")
    }

    @Test("A room the Focus filter shuts out is silenced and delivered quietly")
    func aShutOutRoomIsQuiet() {
        let filter = FocusFilter(rooms: [other], showsPreviews: true)
        let banner = WhatArrived.since(
            nothingSeenYet, post: nil, ask: nil, message: message(), in: world(filter: filter))
        #expect(banner?.copy == MessageNotification.generic)
        #expect(banner?.quietly == true, "a room outside the Focus rang at full volume")
    }

    @Test("A room the Focus filter allows is not quiet")
    func anAllowedRoomIsNotQuiet() {
        let filter = FocusFilter(rooms: [room], showsPreviews: true)
        let banner = WhatArrived.since(
            nothingSeenYet, post: nil, ask: nil, message: message(), in: world(filter: filter))
        #expect(banner?.quietly == false)
        #expect(banner?.copy.body == "are you coming")
    }

    // MARK: The preview switch, which is the one this pass was about

    @Test("Previews hidden withholds a message's words")
    func previewsHiddenWithholdsAMessage() {
        let filter = FocusFilter(rooms: [], showsPreviews: false)
        let banner = WhatArrived.since(
            nothingSeenYet, post: nil, ask: nil, message: message(), in: world(filter: filter))
        #expect(banner?.copy.title == "Hangar 7")
        #expect(banner?.copy.subtitle == "Alice")
        #expect(banner?.copy.body.isEmpty == true)
    }

    @Test("Previews hidden withholds a post's words too")
    func previewsHiddenWithholdsAPost() {
        let filter = FocusFilter(rooms: [], showsPreviews: false)
        let banner = WhatArrived.since(
            nothingSeenYet, post: post(), ask: nil, message: nil, in: world(filter: filter))
        #expect(banner?.copy.title == "Alice")
        #expect(
            banner?.copy.body.isEmpty == true,
            """
            a Focus filter set to hide what was said put a post's words on the lock screen. \
            The filter's own description offers "whether banners show what was said", and a \
            post's body is what was said.
            """)
    }

    @Test("A room list alone never silences a post, because a post is in no room")
    func theRoomListDoesNotReachAPost() {
        let filter = FocusFilter(rooms: [other], showsPreviews: true)
        let banner = WhatArrived.since(
            nothingSeenYet, post: post(), ask: nil, message: nil, in: world(filter: filter))
        #expect(banner?.copy.body == "the mooring mast drawings are 1:200")
    }

    // MARK: The rule that matters most — a banner never carries a name its words withhold

    @Test("No banner carries a sender unless its words name one")
    func aSenderIsOnlyAttachedWhenItIsNamed() {
        for rung in NotificationLevel.allCases {
            let fromAMessage = WhatArrived.since(
                nothingSeenYet, post: nil, ask: nil, message: message(),
                in: world(level: rung, perRoom: rung))
            if let banner = fromAMessage, banner.sender != nil {
                #expect(
                    rung.showsSender && !banner.copy.isGeneric,
                    """
                    at \(rung) the banner attached Alice as a communication notification — her name \
                    and her face — while its own words withhold the sender.
                    """)
            }

            let fromAPost = WhatArrived.since(
                nothingSeenYet, post: post(), ask: nil, message: nil,
                in: world(level: rung, perRoom: rung))
            if let banner = fromAPost, banner.sender != nil {
                #expect(
                    rung.showsSender && !banner.copy.isGeneric,
                    "at \(rung) a post's banner attached its author while its words withhold them")
            }
        }
    }

    @Test("A generic banner never carries a sender")
    func theGenericBannerIsAnonymous() {
        let banner = WhatArrived.since(
            nothingSeenYet, post: nil, ask: nil, message: message(),
            in: world(level: .nothing, perRoom: .nothing))
        #expect(banner?.copy == MessageNotification.generic)
        #expect(banner?.sender == nil, "the content-free banner still named who wrote it")
    }

    @Test("A message with no author to resolve draws no sender")
    func anUnresolvedAuthorIsNoSender() {
        let world = WhatArrived.Surroundings(
            filter: FocusFilter(), defaultLevel: .everything,
            levelForRoom: { _ in .everything }, isDirect: { _ in false },
            authorOfMessage: { _, _ in nil })
        let banner = WhatArrived.since(
            nothingSeenYet, post: nil, ask: nil, message: message(), in: world)
        #expect(banner?.copy.body == "are you coming")
        #expect(banner?.sender == nil)
    }
}
