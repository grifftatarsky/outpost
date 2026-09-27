import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@Suite("What a launch writes")
@MainActor
struct WhatALaunchWritesTests {
    @Test("Growing the session's log one entry at a time costs what growing a plain one does")
    func theSessionsLogGrowsInPlace() async throws {
        var alice = Author()
        var entries: [Entry] = []
        for step in 0..<2_000 {
            entries.append(try alice.post("\(step)", at: Date(timeIntervalSince1970: Double(step))))
        }
        var plain = Replica()
        try plain.meet(alice)
        let checked = await plain.signatureChecks(for: entries)
        let session = TestSession.make()
        session.replica = plain

        var started = Date()
        for entry in entries { try plain.integrate(entry, checked: checked) }
        let alone = Date().timeIntervalSince(started)

        started = Date()
        for entry in entries { try session.replica.integrate(entry, checked: checked) }
        let inTheSession = Date().timeIntervalSince(started)

        #expect(session.replica.entryCount == 2_000, "precondition: every entry went in")
        #expect(
            inTheSession < alone * 3 + 0.05,
            """
            Growing the session's log took \(Int(inTheSession * 1_000))ms against \(Int(alone * 1_000))ms \
            for a plain replica. A `didSet` on `replica` that reads `oldValue` copies the whole log \
            before every change, which made opening the app quadratic in the length of the log.
            """)
    }

    @Test("Opening the app again writes no room key it already kept")
    func aRelaunchWritesNoKeyItKept() async throws {
        let keychain = InMemoryKeychainStore()
        let directory = TestScratch.root.appending(path: "carpenter-launch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = TestSession.make(keychain: keychain, at: directory)
        await first.load()
        try await first.createIdentity(displayName: "Alice")
        for index in 0..<3 {
            let room = try await first.createRoom(named: "Room \(index)")
            try await first.send("hello", to: room)
        }
        let written = await keychain.writes

        let again = TestSession.make(keychain: keychain, at: directory)
        await again.load()

        let rewritten = await keychain.writes - written

        #expect(again.rooms.count == 3, "precondition: the rooms came back")
        #expect(
            rewritten == 0,
            """
            A relaunch wrote \(rewritten) keychain item(s). Every room key was written back, each \
            with a save of the whole state file, on every launch.
            """)
    }
}

private actor CountedDocuments: DocumentStore {
    private let inner: FileDocumentStore
    private(set) var saves = 0
    private var failsNext = false

    init(_ url: URL) { inner = FileDocumentStore(url: url) }

    func failNextSave() { failsNext = true }

    func load<Value: Decodable & Sendable>(_ type: Value.Type) async throws -> Value? {
        try await inner.load(type)
    }

    func save(_ value: some Encodable & Sendable) async throws {
        if failsNext {
            failsNext = false
            throw CocoaError(.fileWriteNoPermission)
        }
        saves += 1
        try await inner.save(value)
    }

    func clear() async throws { try await inner.clear() }
}

@Suite("What a sync round writes", .serialized)
@MainActor
struct WhatARoundWritesTests {
    private func counted() -> (AppSession, CountedDocuments, InMemoryKeychainStore) {
        let root = TestScratch.root.appending(path: "carpenter-round-\(UUID().uuidString)")
        let documents = CountedDocuments(root.appending(path: "state.json"))
        let keychain = InMemoryKeychainStore()
        let session = AppSession(
            storage: SessionStorage(
                keychain: keychain, log: FileLogStore(url: root.appending(path: "log.carpenter")),
                documents: documents, media: MemoryMediaStore()),
            clock: TestClock(now: TestSession.now))
        return (session, documents, keychain)
    }

    private func joined() async throws -> (
        alice: AppSession, bob: AppSession, bobDocuments: CountedDocuments, bobKeychain: InMemoryKeychainStore,
        mailbox: InMemoryMailbox, room: RoomID
    ) {
        let mailbox = InMemoryMailbox()
        let (alice, _, _) = counted()
        let (bob, bobDocuments, bobKeychain) = counted()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        for _ in 0..<3 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, bobDocuments, bobKeychain, mailbox, room)
    }

    @Test("A round that brings nothing writes nothing")
    func anIdleRoundWritesNothing() async throws {
        let (_, bob, documents, keychain, mailbox, _) = try await joined()
        try await bob.sync(through: mailbox)
        let before = await documents.saves
        let keysBefore = await keychain.writes

        try await bob.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        let written = await documents.saves - before
        let keysWritten = await keychain.writes - keysBefore
        #expect(keysWritten == 0, "two rounds that brought nothing wrote \(keysWritten) keychain item(s)")
        #expect(
            written == 0,
            """
            Two rounds that brought nothing wrote the whole state file \(written) time(s). The \
            foreground loop runs a round every few seconds and every push runs one.
            """)
    }

    @Test("A round that brings a message writes what changed")
    func aRoundWithNewsWrites() async throws {
        let (alice, bob, documents, _, mailbox, room) = try await joined()
        try await alice.send("hello", to: room)
        try await alice.sync(through: mailbox)
        let before = await documents.saves

        try await bob.sync(through: mailbox)

        #expect(bob.messages(in: room).contains { $0.body == "hello" }, "precondition: it arrived")
        #expect(await documents.saves > before)
    }

    @Test("A write that did not land is made again, even when nothing else has changed")
    func aFailedWriteIsRetried() async throws {
        let (_, bob, documents, _, _, _) = try await joined()
        bob.persisted.greetedRooms.append(RoomID())
        await documents.failNextSave()
        await #expect(throws: CocoaError.self) { try await bob.saveState() }
        let before = await documents.saves

        try await bob.saveState()

        #expect(await documents.saves == before + 1, "the state that failed to land was taken as written")
    }
}
