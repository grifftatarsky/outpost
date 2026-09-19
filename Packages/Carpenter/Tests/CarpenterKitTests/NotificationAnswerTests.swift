@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing
import UserNotifications

@MainActor
@Suite("Answering a message from its notification", .serialized)
struct NotificationAnswerTests {
    private let room = RoomID()

    private var info: [AnyHashable: Any] { NotificationAnswer.userInfo(for: room) }

    // MARK: What the system hands back

    @Test("Tapping the banner itself opens the app, as it always did")
    func theBannerOpens() {
        #expect(
            NotificationAnswer.from(action: UNNotificationDefaultActionIdentifier, userInfo: info, text: nil)
                == .open)
        #expect(NotificationAnswer.from(action: UNNotificationDefaultActionIdentifier, userInfo: [:], text: nil) == .open)
    }

    @Test("Reply carries the words and the room, trimmed")
    func replyCarriesTheWords() {
        let answer = NotificationAnswer.from(
            action: NotificationAnswer.replyAction, userInfo: info, text: "  on my way\n")
        #expect(answer == .reply(room, "on my way"))
    }

    @Test("A reply with nothing in it sends nothing")
    func anEmptyReplySendsNothing() {
        for text in [nil, "", "   \n "] {
            #expect(
                NotificationAnswer.from(action: NotificationAnswer.replyAction, userInfo: info, text: text)
                    == .nothing)
        }
    }

    @Test("Mark as Read carries the room")
    func markReadCarriesTheRoom() {
        #expect(
            NotificationAnswer.from(action: NotificationAnswer.markReadAction, userInfo: info, text: nil)
                == .markRead(room))
    }

    @Test("An action on a banner that names no room does nothing rather than guessing one")
    func noRoomNoAnswer() {
        for info: [AnyHashable: Any] in [[:], [NotificationAnswer.roomKey: "not a room"], [NotificationAnswer.roomKey: 7]] {
            #expect(
                NotificationAnswer.from(action: NotificationAnswer.markReadAction, userInfo: info, text: nil)
                    == .nothing)
            #expect(
                NotificationAnswer.from(action: NotificationAnswer.replyAction, userInfo: info, text: "hi")
                    == .nothing)
        }
    }

    // MARK: What the banner offers

    @Test("A message's banner offers Reply with a field, then Mark as Read, and neither runs locked")
    func theCategory() throws {
        let categories = NotificationAnswer.categories
        #expect(categories.map(\.identifier) == [NotificationAnswer.messageCategory])
        let category = try #require(categories.first)
        #expect(
            category.hiddenPreviewsBodyPlaceholder == "Message",
            "with previews hidden the banner would say only Notification")
        #expect(!category.options.contains(.hiddenPreviewsShowTitle), "a hidden preview would still name the room")
        let actions = category.actions
        #expect(actions.map(\.identifier) == [NotificationAnswer.replyAction, NotificationAnswer.markReadAction])
        #expect(actions.first is UNTextInputNotificationAction, "Reply has no field to write in")
        #expect(!(actions.last is UNTextInputNotificationAction))
        for action in actions {
            #expect(
                action.options.contains(.authenticationRequired),
                "\(action.identifier) would read keys and write the log on a locked device")
            #expect(
                !action.options.contains(.foreground),
                "\(action.identifier) opens the app, which answering from a banner is for not doing")
            #expect(!action.options.contains(.destructive))
        }
    }

    // MARK: A reply that could not be sent

    @Test("A reply that could not be sent comes back as a notification in its room, never silently dropped")
    func aFailedReplyComesBack() {
        let shown = NotificationAnswer.notSent("on my way", in: room, named: "Hangar 7", keptAsDraft: false, showingWords: true)
        #expect(shown.title == "Hangar 7")
        #expect(shown.body.contains("on my way"), "the member's words were lost with the reply")
        #expect(shown.threadIdentifier == MessageNotification.thread(for: room))
        #expect(NotificationAnswer.from(action: UNNotificationDefaultActionIdentifier, userInfo: shown.userInfo, text: nil) == .open)
        #expect(shown.categoryIdentifier.isEmpty, "a failure notice offered Reply, which is what just failed")
    }

    @Test("A reply kept as a draft is not repeated in the notice, which says where it is")
    func aKeptReplyIsNotRepeated() {
        let kept = NotificationAnswer.notSent("on my way", in: room, named: "Hangar 7", keptAsDraft: true, showingWords: true)
        #expect(!kept.body.contains("on my way"))
        #expect(kept.body.contains("draft"))
    }

    @Test("With previews hidden, the failure notice says a reply failed without repeating it")
    func aFailedReplyKeepsPreviewsHidden() {
        let hidden = NotificationAnswer.notSent("on my way", in: room, named: nil, keptAsDraft: false, showingWords: false)
        #expect(!hidden.body.contains("on my way"))
        #expect(!hidden.title.isEmpty)
    }

    // MARK: What answering does

    private func joined() async throws -> (alice: AppSession, bob: AppSession, room: RoomID, mailbox: InMemoryMailbox) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        try await alice.send("are you coming", to: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        return (alice, bob, room, mailbox)
    }

    private func unread(_ session: AppSession, _ room: RoomID) -> Bool {
        session.rooms.first { $0.id == room }?.hasUnread ?? false
    }

    @Test("A reply is sealed and sent like one from the composer, and reaches the room")
    func aReplyReachesTheRoom() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        #expect(unread(bob, room))

        try await bob.answer(.reply(room, "on my way"))
        #expect(!unread(bob, room), "replying from the banner left the room unread")

        try await bob.sync(through: mailbox)
        let written = await mailbox.storedWireBytes
        #expect(!written.isEmpty, "the reply was never written to the mailbox")
        #expect(
            !(written.contains { $0.range(of: Data("on my way".utf8)) != nil }),
            "a reply from a banner reached the mailbox readable")

        try await alice.sync(through: mailbox)
        let last = try #require(alice.messages(in: room).last)
        #expect(last.body == "on my way")
        #expect(last.author.id == bob.viewer.id)
    }

    @Test("Mark as Read clears the room without sending anything")
    func markReadClearsTheRoom() async throws {
        let (_, bob, room, _) = try await joined()
        let before = bob.messages(in: room).count
        try await bob.answer(.markRead(room))
        #expect(!unread(bob, room))
        #expect(BadgeCount.of(bob.rooms) == 0)
        #expect(bob.messages(in: room).count == before)
    }

    @Test("Two loads at once do the work once, so an answer from the background cannot race the window's bring-up")
    func concurrentLoadsShareOne() async throws {
        let keychain = CountingKeychain()
        let bob = TestSession.make(keychain: keychain)
        await bob.load()
        try await bob.createIdentity(displayName: "Bob")

        let before = await keychain.reads
        await bob.load()
        let one = await keychain.reads - before
        #expect(one > 0)

        let again = await keychain.reads
        async let first: Void = bob.load()
        async let second: Void = bob.load()
        _ = await (first, second)
        #expect(await keychain.reads - again == one, "two loads in flight read the keys twice and raced each other")
        #expect(bob.state == .ready)
    }
}

private actor CountingKeychain: KeychainStore {
    private let inner = InMemoryKeychainStore()
    private(set) var reads = 0

    func data(for key: KeychainKey) async throws -> Data? {
        reads += 1
        return try await inner.data(for: key)
    }

    func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws {
        try await inner.set(data, for: key, scope: scope)
    }

    func remove(_ key: KeychainKey) async throws { try await inner.remove(key) }

    func removeAll() async throws { try await inner.removeAll() }
}
