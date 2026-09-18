import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("A message typed mid-sync", .serialized)
@MainActor
struct SendRaceTests {
    private func scratch() -> URL {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-race-\(UUID().uuidString)")
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

    private actor SlowMailbox: Mailbox {
        private let inner = InMemoryMailbox()
        private var duringPut: (@Sendable () async -> Void)?

        func onPut(_ work: @escaping @Sendable () async -> Void) { duringPut = work }

        func put(_ packet: SyncPacket) async throws {
            if let duringPut { self.duringPut = nil; await duringPut() }
            try await inner.put(packet)
        }

        func fetch(for tags: Set<RecipientTag>) async throws -> [SyncPacket] {
            try await inner.fetch(for: tags)
        }
        func acknowledge(_ id: PacketID, by tags: Set<RecipientTag>) async throws {
            try await inner.acknowledge(id, by: tags)
        }
        func pendingDeliveries() async throws -> [PacketID: Set<RecipientTag>] {
            try await inner.pendingDeliveries()
        }
        func ring(_ bell: MessageBell) async throws { try await inner.ring(bell) }
    }

    @Test("A message appended during a sync is still sent afterwards")
    func appendedMidSyncIsNotLost() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = SlowMailbox()

        let alice = session(clock)
        let bob = session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        try await alice.send("first", to: room)

        await mailbox.onPut { @Sendable in
            await MainActor.run { Task { try? await alice.send("typed while sending", to: room) } }
            try? await Task.sleep(for: .milliseconds(30))
        }
        try await alice.sync(through: mailbox)

        for _ in 0..<3 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(
            bob.messages(in: room).contains { $0.body == "typed while sending" },
            "a message typed during a sync was marked sent without ever being written")
        #expect(bob.messages(in: room).contains { $0.body == "first" })
    }

    @Test("A message typed during a sync still rings the recipient")
    func ringSurvivesAConcurrentRound() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = SlowMailbox()

        let alice = session(clock)
        let bob = session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<3 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        await mailbox.onPut { @Sendable in
            await MainActor.run { Task { try? await alice.send("ring for this", to: room) } }
            try? await Task.sleep(for: .milliseconds(30))
        }
        try await alice.sync(through: mailbox)

        var rung = 0
        for _ in 0..<3 {
            rung += try await alice.sync(through: mailbox).bellsRung
            try await bob.sync(through: mailbox)
        }

        #expect(
            bob.messages(in: room).contains { $0.body == "ring for this" },
            "precondition: the message itself arrived")
        #expect(rung >= 1, "the message arrived and nobody was told")
    }

    @Test("An unsent message is still unsent after a round that did not carry it")
    func frontierOnlyCoversWhatWasPacked() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()

        let alice = session(clock)
        let bob = session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        try await alice.send("one", to: room)
        let first = try await alice.sync(through: mailbox)
        #expect(first.entriesSent > 0)

        try await alice.send("two", to: room)
        let second = try await alice.sync(through: mailbox)
        #expect(second.entriesSent > 0, "the second message was never offered to the mailbox")

        for _ in 0..<2 { try await bob.sync(through: mailbox) }
        #expect(bob.messages(in: room).contains { $0.body == "one" })
        #expect(bob.messages(in: room).contains { $0.body == "two" })
    }
}
