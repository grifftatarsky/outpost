@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Unread", .serialized)
struct UnreadTests {
    private func joined(
        bobAt directory: URL? = nil, bobKeychain: any KeychainStore = InMemoryKeychainStore()
    ) async throws -> (alice: AppSession, bob: AppSession, room: ConversationID, mailbox: InMemoryMailbox) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make(keychain: bobKeychain, at: directory)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, room, mailbox)
    }

    private func unread(_ session: AppSession, _ room: ConversationID) -> Bool {
        session.rooms.first { $0.id == room }?.hasUnread ?? false
    }

    private func alicaSays(
        _ text: String, to room: ConversationID, from alice: AppSession, to bob: AppSession,
        through mailbox: InMemoryMailbox
    ) async throws {
        try await alice.send(text, to: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
    }

    // MARK: What makes a room unread

    @Test("A message from somebody else leaves a dot on their room")
    func somebodyElsesMessageIsUnread() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        try await alicaSays("are you there", to: room, from: alice, to: bob, through: mailbox)

        #expect(unread(bob, room), "a message arrived and the room did not say so")
        #expect(BadgeCount.of(bob.rooms) == 1)
    }

    @Test("Your own message never leaves a dot on your own room")
    func yourOwnMessageIsNotUnread() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        try await alicaSays("mine", to: room, from: alice, to: bob, through: mailbox)

        #expect(!unread(alice, room), "the app badged somebody for talking to themselves")
        #expect(BadgeCount.of(alice.rooms) == 0)
    }

    @Test("Being added to a room is not something to read")
    func joiningIsNotUnread() async throws {
        let (_, bob, room, _) = try await joined()
        #expect(!unread(bob, room), "the join itself was counted as unread")
    }

    // MARK: Clearing it

    @Test("Reading the message clears the dot")
    func readingClearsIt() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        try await alicaSays("are you there", to: room, from: alice, to: bob, through: mailbox)
        let arrived = try #require(bob.messages(in: room).last)

        await bob.markSeen(arrived.id, in: room)

        #expect(!unread(bob, room), "the room stayed unread after it was read")
        #expect(BadgeCount.of(bob.rooms) == 0)
    }

    @Test("Unread works for somebody who never turned read receipts on")
    func unreadDoesNotNeedTheReceiptOptIn() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        #expect(!bob.reportsDisplaying, "this test is meaningless if reporting is on by default")

        try await alicaSays("are you there", to: room, from: alice, to: bob, through: mailbox)
        let arrived = try #require(bob.messages(in: room).last)
        await bob.markSeen(arrived.id, in: room)

        #expect(!unread(bob, room), "the dot only clears for members who report their reading")
    }

    @Test("Scrolling back through older messages does not put the dot back")
    func theMarkOnlyMovesForward() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        try await alicaSays("one", to: room, from: alice, to: bob, through: mailbox)
        try await alicaSays("two", to: room, from: alice, to: bob, through: mailbox)
        let arrived = bob.messages(in: room)
        try #require(arrived.count == 2)

        await bob.markSeen(arrived[1].id, in: room)
        await bob.markSeen(arrived[0].id, in: room)

        #expect(!unread(bob, room), "reading an older message marked the room unread again")
    }

    @Test("Marking a room read from the list clears it and tells nobody")
    func markingTheRoomReadTellsNobody() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        await bob.setReportsDisplaying(true)
        try await alicaSays("are you there", to: room, from: alice, to: bob, through: mailbox)
        let before = bob.messages(in: room).count

        await bob.markRoomRead(room)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        #expect(!unread(bob, room))
        #expect(
            bob.messages(in: room).count == before,
            "sweeping a room off the list put an entry in it")
        #expect(
            alice.messages(in: room).last?.delivery.wasDisplayed != true,
            "the app told the room somebody had read a message they only filed away")
    }

    // MARK: What is not unread, because it is not drawn

    @Test("A message this member hid is not unread")
    func hiddenIsNotUnread() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        try await alicaSays("never mind", to: room, from: alice, to: bob, through: mailbox)
        let arrived = try #require(bob.messages(in: room).last)

        await bob.hide(arrived.id)

        #expect(!unread(bob, room), "a message they put away themselves still badged them")
    }

    @Test("A withdrawn message is not unread")
    func withdrawnIsNotUnread() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        try await alice.send("said too fast", to: room)
        let mine = try #require(alice.messages(in: room).last)
        try await alice.withdraw(mine.id)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        try #require(bob.messages(in: room).last?.isWithdrawn == true)
        #expect(!unread(bob, room), "a room was marked unread for a message with no words in it")
    }

    // MARK: Across a relaunch

    @Test("A room read on this device is still read after a relaunch")
    func theMarkSurvivesARelaunch() async throws {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-unread-\(UUID().uuidString)")
        let keychain = InMemoryKeychainStore()
        let (alice, bob, room, mailbox) = try await joined(bobAt: directory, bobKeychain: keychain)

        try await alicaSays("are you there", to: room, from: alice, to: bob, through: mailbox)
        await bob.markSeen(try #require(bob.messages(in: room).last).id, in: room)
        try #require(!unread(bob, room))

        let relaunched = TestSession.make(keychain: keychain, at: directory)
        await relaunched.load()

        #expect(
            !unread(relaunched, room),
            "the room came back unread, so the read mark did not survive the launch")
    }

    // MARK: The rule itself

    @Test("A read mark this device cannot find reads as nothing read")
    func anUnknownMarkShowsUnread() throws {
        let chain = EpochChain.create(room: ConversationID.room(UUID()))
        var alice = Author(chain: chain.chain)
        let room = chain.chain.room
        let said = try alice.append(
            try Payload.post("hello"), at: TestSession.now, room: room)
        let rendered = Fold.render([said], using: chain.chain)

        #expect(
            Projection.hasUnread(
                in: rendered, for: Identity.generate().id,
                readThrough: EntryHash(rawValue: Data([0xDE, 0xAD])), undrawn: []),
            "an unfindable mark hid a message that had never been read")
    }

    @Test("With nobody reading, nothing is unread")
    func noViewerMeansNoUnread() throws {
        let chain = EpochChain.create(room: ConversationID.room(UUID()))
        var alice = Author(chain: chain.chain)
        let said = try alice.append(
            try Payload.post("hello"), at: TestSession.now, room: chain.chain.room)

        #expect(
            !Projection.hasUnread(
                in: Fold.render([said], using: chain.chain), for: nil, readThrough: nil, undrawn: []))
    }
}
