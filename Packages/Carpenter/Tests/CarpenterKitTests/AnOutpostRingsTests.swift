import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("An Outpost rings", .serialized)
@MainActor
struct AnOutpostRingsTests {
    private func scratch() -> URL {
        URL.temporaryDirectory.appending(path: "carpenter-outpost-bell-\(UUID().uuidString)")
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
    ) async throws -> (alice: AppSession, bob: AppSession, post: OutpostPost) {
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
        try await alice.send("first light", to: try #require(alice.ownOutpost))
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        let post = try #require(
            bob.feed().first { $0.author.id == alice.viewer.id },
            "precondition: Bob can see Alice's post")
        return (alice, bob, post)
    }

    @Test("Commenting on somebody's post rings them")
    func commentRings() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (_, bob, post) = try await aWallBobCanRead(clock, mailbox)

        let before = await mailbox.bells.count
        try await bob.comment(on: post, text: "and the second")
        let report = try await bob.sync(through: mailbox)
        let after = await mailbox.bells.count

        #expect(report.bellsRung >= 1, "a comment was written and its author was told nothing")
        #expect(after > before)
    }

    @Test("Reacting to somebody's post rings them")
    func reactionRings() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (_, bob, post) = try await aWallBobCanRead(clock, mailbox)

        let before = await mailbox.bells.count
        try await bob.react(to: post, emoji: "🔥")
        let report = try await bob.sync(through: mailbox)

        #expect(report.bellsRung >= 1, "a reaction was written and its author was told nothing")
        #expect(await mailbox.bells.count > before)
    }

    @Test("Taking a reaction back rings nobody")
    func unreactingRingsNobody() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (_, bob, post) = try await aWallBobCanRead(clock, mailbox)

        try await bob.react(to: post, emoji: "🔥")
        _ = try await bob.sync(through: mailbox)

        let before = await mailbox.bells.count
        try await bob.react(to: post, emoji: nil)
        let report = try await bob.sync(through: mailbox)

        #expect(report.bellsRung == 0, "taking a like back woke somebody up")
        #expect(await mailbox.bells.count == before)
    }

    @Test("Commenting on your own post rings nobody who did not ask")
    func ownPostRingsNobodyUnasked() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, _, _) = try await aWallBobCanRead(clock, mailbox)

        let mine = try #require(alice.feed().first { $0.isMine })
        let before = await mailbox.bells.count
        try await alice.comment(on: mine, text: "a note to myself")
        let report = try await alice.sync(through: mailbox)

        #expect(
            report.bellsRung == 0,
            "commenting on your own post rang somebody who never asked to be woken for this wall")
        #expect(await mailbox.bells.count == before)
    }
}
