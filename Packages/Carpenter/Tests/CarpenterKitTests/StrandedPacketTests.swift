import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("A packet whose address has rotated", .serialized)
@MainActor
struct StrandedPacketTests {
    private func scratch() -> URL {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-stranded-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func session(_ clock: TestClock) -> AppSession {
        let directory = scratch()
        return AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(),
                log: FileLogStore(url: directory.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json"))
            ),
            clock: clock
        )
    }

    @Test("A message sent before the address rotates still arrives after it")
    func acrossOneRotation() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()

        let alice = session(clock)
        let bob = session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())

        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        try await alice.send("written just before midnight", to: room)
        try await alice.sync(through: mailbox)

        clock.advance(by: SyncSession.tagWindow)

        try await bob.sync(through: mailbox)
        #expect(
            bob.messages(in: room).contains { $0.body == "written just before midnight" },
            "the packet was addressed to an address nobody asks for any more")
    }

    @Test("A message several rotations old is still collected")
    func acrossSeveralRotations() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()

        let alice = session(clock)
        let bob = session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        try await alice.send("lost for days", to: room)
        try await alice.sync(through: mailbox)

        clock.advance(by: SyncSession.tagWindow * 4)

        try await bob.sync(through: mailbox)
        #expect(bob.messages(in: room).contains { $0.body == "lost for days" })
    }

    @Test("A packet collected under an old address is acknowledged and cleared")
    func acknowledgedUnderTheOldAddress() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()

        let alice = session(clock)
        let bob = session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        try await alice.send("acknowledge me", to: room)
        try await alice.sync(through: mailbox)

        clock.advance(by: SyncSession.tagWindow * 2)
        try await bob.sync(through: mailbox)

        #expect(
            try await mailbox.pendingRecipients().isEmpty,
            "the packet was read but left outstanding, so it will never be deleted")
    }
}
