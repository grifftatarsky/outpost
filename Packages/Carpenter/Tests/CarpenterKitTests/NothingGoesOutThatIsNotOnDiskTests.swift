import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp
@testable import CarpenterKit

private actor HeldLogStore: LogStore {
    let inner = MemoryLogStore()
    private var holding = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var appendsArrived = 0

    func hold() { holding = true }

    func release() {
        holding = false
        for writer in waiting { writer.resume() }
        waiting = []
    }

    func append(_ entries: [Entry]) async throws {
        appendsArrived += 1
        if holding { await withCheckedContinuation { waiting.append($0) } }
        try await inner.append(entries)
    }

    func loadAll() async throws -> LoadedLog { try await inner.loadAll() }
    func removeAll() async throws { try await inner.removeAll() }

    @discardableResult
    func removeEntries(where shouldRemove: @escaping @Sendable (Entry) -> Bool) async throws -> Int {
        try await inner.removeEntries(where: shouldRemove)
    }
}

@Suite("A member's own entry exists only once it is on disk", .serialized)
@MainActor
struct OwnEntriesReachTheDiskFirstTests {
    private func directory() -> URL {
        let url = TestScratch.root.appending(path: "carpenter-own-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func session(
        log: any LogStore, keychain: any KeychainStore, in directory: URL, clock: TestClock
    ) -> AppSession {
        AppSession(
            storage: SessionStorage(
                keychain: keychain, log: log,
                documents: FileDocumentStore(url: directory.appending(path: "state.json"))),
            clock: clock)
    }

    private func introduce(_ alice: AppSession, _ bob: AppSession, through mailbox: InMemoryMailbox) async throws -> RoomID {
        let room = try await alice.createRoom(named: "Kitchen")
        let invite = try await alice.invite(
            joinerCode: await bob.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [alice, bob] { try await session.sync(through: mailbox) }
        }
        return room
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !(await condition()), Date() < deadline { await Task.yield() }
    }

    @Test("A send the disk refused is gone: not shown, not offered, and its number is free")
    func aRefusedSendLeavesNoTrace() async throws {
        let (log, keychain, directory) = (MemoryLogStore(), InMemoryKeychainStore(), directory())
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let alice = session(log: log, keychain: keychain, in: directory, clock: clock)
        let bob = TestSession.make(clock: clock)
        for member in [alice, bob] { await member.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await introduce(alice, bob, through: mailbox)
        let head = alice.head

        await log.refuse(true)
        await #expect(throws: (any Error).self) { try await alice.send("never written", to: room) }

        #expect(alice.head == head, "the number of an entry the disk refused was used up")
        #expect(!alice.messages(in: room).contains { $0.body == "never written" })
        #expect(!alice.unsentEntries().contains { $0.seq > head?.seq ?? 0 })

        await log.refuse(false)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        #expect(
            !bob.messages(in: room).contains { $0.body == "never written" },
            "a contact was sent an entry that is not on this device's disk")

        let reopened = session(log: log, keychain: keychain, in: directory, clock: clock)
        await reopened.load()
        try await reopened.send("written", to: room)
        try await reopened.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        #expect(bob.messages(in: room).contains { $0.body == "written" })
        #expect(bob.replica.forks.isEmpty, "the member's own device forked its feed")
    }

    @Test("A send the disk refused does not reach the member's other devices")
    func aRefusedSendIsNotPublished() async throws {
        let (log, keychain, directory) = (MemoryLogStore(), InMemoryKeychainStore(), directory())
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay()
        let phone = session(log: log, keychain: keychain, in: directory, clock: clock)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        await phone.load()
        try await phone.createIdentity(displayName: "Griff")
        let room = try await phone.createRoom(named: "Kitchen")

        let tablet = TestSession.make(keychain: await keychain.sibling(), clock: clock)
        tablet.syncDevices(through: InMemoryEntrySync(relay: relay))
        await tablet.load()
        try await phone.approveNewDevice(tablet)
        await tablet.settleDeviceSync { tablet.rooms.contains { $0.id == room } }

        await log.refuse(true)
        await #expect(throws: (any Error).self) { try await phone.send("never written", to: room) }
        await log.refuse(false)
        for _ in 0..<4 {
            await phone.settleDeviceSync()
            await phone.refreshDeviceSync()
            await tablet.refreshDeviceSync()
            await tablet.settleDeviceSync()
        }

        #expect(
            !tablet.messages(in: room).contains { $0.body == "never written" },
            "another device was given an entry that is not on disk")

        try await phone.send("written", to: room)
        for _ in 0..<4 {
            await phone.settleDeviceSync()
            await tablet.refreshDeviceSync()
            await tablet.settleDeviceSync()
        }
        #expect(tablet.messages(in: room).contains { $0.body == "written" }, "the control: mail stopped altogether")
        #expect(tablet.replica.forks.isEmpty)
    }

    @Test("Two sends racing a slow disk take two numbers, in order")
    func racingSendsTakeTwoNumbers() async throws {
        let log = HeldLogStore()
        let alice = session(log: log, keychain: InMemoryKeychainStore(), in: directory(), clock: TestClock(now: TestSession.now))
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let room = try await alice.createRoom(named: "Kitchen")
        let before = await log.appendsArrived

        await log.hold()
        let first = Task { try await alice.send("first", to: room) }
        await waitUntil { await log.appendsArrived == before + 1 }
        let second = Task { try await alice.send("second", to: room) }
        await Task.yield()
        await log.release()
        try await first.value
        try await second.value

        let stored = await log.inner.stored
        let own = stored.filter { $0.feedKey == alice.replica.allEntries.last?.feedKey }
        #expect(Set(own.map(\.seq)).count == own.count, "two entries share a number")
        #expect(alice.replica.forks.isEmpty)
        #expect(alice.messages(in: room).map(\.body).suffix(2) == ["first", "second"])
    }

    @Test("An entry on its way to disk is not offered, and goes out once it lands")
    func anEntryOnItsWayIsNotOffered() async throws {
        let log = HeldLogStore()
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let alice = session(log: log, keychain: InMemoryKeychainStore(), in: directory(), clock: clock)
        let bob = TestSession.make(clock: clock)
        for member in [alice, bob] { await member.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await introduce(alice, bob, through: mailbox)
        let before = await log.appendsArrived

        await log.hold()
        let sending = Task { try await alice.send("on its way", to: room) }
        await waitUntil { await log.appendsArrived == before + 1 }

        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        #expect(!bob.messages(in: room).contains { $0.body == "on its way" })

        await log.release()
        try await sending.value
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        #expect(bob.messages(in: room).contains { $0.body == "on its way" })
    }

    @Test("A send that fails lets the next one through")
    func aFailedSendDoesNotBlockTheNext() async throws {
        let log = MemoryLogStore()
        let alice = session(log: log, keychain: InMemoryKeychainStore(), in: directory(), clock: TestClock(now: TestSession.now))
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let room = try await alice.createRoom(named: "Kitchen")

        await log.refuse(true)
        await #expect(throws: (any Error).self) { try await alice.send("refused", to: room) }
        await log.refuse(false)
        try await alice.send("written", to: room)

        #expect(alice.messages(in: room).map(\.body) == ["written"])
    }
}
