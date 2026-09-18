import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("What the tabs badge", .serialized)
@MainActor
struct WhatTheTabsBadgeTests {
    private func scratch() -> URL {
        URL.temporaryDirectory.appending(path: "carpenter-badge-\(UUID().uuidString)")
    }

    private func session(_ clock: TestClock) throws -> AppSession {
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(),
                log: FileLogStore(url: directory.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json"))
            ),
            clock: clock)
    }

    private func aWallBobCanRead(
        _ clock: TestClock, _ mailbox: InMemoryMailbox
    ) async throws -> (alice: AppSession, bob: AppSession, room: RoomID) {
        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        try await alice.allowOutpost(bob.viewer.id, everything: true)
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        clock.advance(by: 60)
        return (alice, bob, room)
    }

    @Test("Seeing a post in the feed clears the Outposts badge")
    func feedClearsTheBadge() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob, _) = try await aWallBobCanRead(clock, mailbox)

        try await alice.send("first light", to: nil)
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(
            bob.outpostAuthorsWithUnseen().contains(alice.viewer.id),
            "precondition: Alice's post is unseen, so the tab is badged")

        let post = try #require(bob.feed().first { $0.author.id == alice.viewer.id })
        await bob.markOutpostSeen(post)

        #expect(
            bob.outpostAuthorsWithUnseen().isEmpty,
            "reading the post in the feed left the badge on the tab")
    }

    @Test("Seeing an older post does not clear the newer ones above it")
    func seeingOneDoesNotClearTheRest() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob, _) = try await aWallBobCanRead(clock, mailbox)

        try await alice.send("older", to: nil)
        clock.advance(by: 60)
        try await alice.send("newer", to: nil)
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        #expect(bob.unseenPosts(from: alice.viewer.id) == 2, "precondition: two posts are unseen")

        let older = try #require(
            bob.feed().filter { $0.author.id == alice.viewer.id }.min { $0.postedAt < $1.postedAt })
        await bob.markOutpostSeen(older)

        #expect(
            bob.unseenPosts(from: alice.viewer.id) == 1,
            "seeing the older post cleared the newer one nobody had reached")
    }

    @Test("A mark never goes backwards")
    func marksOnlyAdvance() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob, _) = try await aWallBobCanRead(clock, mailbox)

        try await alice.send("older", to: nil)
        clock.advance(by: 60)
        try await alice.send("newer", to: nil)
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        let theirs = bob.feed().filter { $0.author.id == alice.viewer.id }
        let newer = try #require(theirs.max { $0.postedAt < $1.postedAt })
        let older = try #require(theirs.min { $0.postedAt < $1.postedAt })

        await bob.markOutpostSeen(newer)
        #expect(bob.unseenPosts(from: alice.viewer.id) == 0)

        await bob.markOutpostSeen(older)
        #expect(
            bob.unseenPosts(from: alice.viewer.id) == 0,
            "seeing an older post afterwards made already-read posts unread again")
    }

    @Test("Your own posts are never unseen")
    func ownPostsNeverBadge() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, _, _) = try await aWallBobCanRead(clock, mailbox)

        try await alice.send("talking to myself", to: nil)
        try await alice.sync(through: mailbox)

        #expect(alice.unseenPosts(from: alice.viewer.id) == 0)
        #expect(!alice.outpostAuthorsWithUnseen().contains(alice.viewer.id))
    }

    @Test("A room with something unread badges, and reading it clears")
    func roomsBadge() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob, room) = try await aWallBobCanRead(clock, mailbox)

        try await alice.send("are you coming", to: room)
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(
            bob.rooms.filter(\.hasUnread).count == 1,
            "precondition: Bob has one room with something unread")
        #expect(
            alice.rooms.filter(\.hasUnread).count == 0,
            "your own message made your own room unread")

        await bob.markRoomRead(room)
        #expect(bob.rooms.filter(\.hasUnread).count == 0, "reading the room left it badged")
    }
}
