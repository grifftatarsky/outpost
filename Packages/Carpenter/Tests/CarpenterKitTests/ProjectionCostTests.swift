import Foundation
import Testing

@testable import CarpenterApp
@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("What drawing a screen costs")
@MainActor
struct ProjectionCostTests {
    private func session() -> AppSession {
        AppSession(storage: TestSession.storage(), clock: TestClock(now: TestSession.now))
    }

    private func populated(rooms roomCount: Int, messagesEach: Int) async throws -> (
        AppSession, [RoomID]
    ) {
        let alice = session()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")

        var rooms: [RoomID] = []
        for index in 0..<roomCount {
            let room = try await alice.createRoom(named: "Room \(index)")
            rooms.append(room)
            for message in 0..<messagesEach {
                try await alice.send("message \(message)", to: room)
            }
        }
        return (alice, rooms)
    }

    @Test("Reading the same state twice folds the log once")
    func readsAreCheapBetweenWrites() async throws {
        let (alice, rooms) = try await populated(rooms: 4, messagesEach: 8)
        guard let room = rooms.first else { return }

        _ = alice.messages(in: room)

        let before = alice.foldCount
        _ = alice.messages(in: room)
        _ = alice.transcript(in: room)
        _ = alice.roster(of: room)
        _ = alice.outpost()
        let folds = alice.foldCount - before

        #expect(
            folds == 0,
            """
            four reads with no write between them folded the log \(folds) time(s). \
            The fold is the whole log; a screen that reads three things should not pay for three.
            """)
    }

    @Test("Refreshing after a write folds the log once, whatever the room count")
    func refreshDoesNotScaleWithRooms() async throws {
        let (alice, rooms) = try await populated(rooms: 6, messagesEach: 4)
        guard let room = rooms.first else { return }
        _ = alice.messages(in: room)

        let before = alice.foldCount
        try await alice.send("one more", to: room)
        let folds = alice.foldCount - before

        #expect(
            folds <= 1,
            """
            one message into a six-room account folded the whole log \(folds) time(s). \
            This used to grow with the number of rooms, on a path that runs every five seconds \
            while a conversation is open.
            """)
    }

    @Test("A write is still visible to the next read")
    func theCacheCannotGoStale() async throws {
        let (alice, rooms) = try await populated(rooms: 2, messagesEach: 2)
        guard let room = rooms.first else { return }

        _ = alice.messages(in: room)
        try await alice.send("after the read", to: room)

        #expect(
            alice.messages(in: room).contains { $0.body == "after the read" },
            "the fold was cached and not invalidated — the worst possible outcome of this change")
    }

    @Test("A room made after a read is visible")
    func newRoomsAreVisible() async throws {
        let (alice, _) = try await populated(rooms: 1, messagesEach: 1)
        _ = alice.rooms

        let fresh = try await alice.createRoom(named: "Made later")
        #expect(alice.rooms.contains { $0.id == fresh })
    }

    @Test("Drawing the root screen does not re-decrypt the log every time")
    func rootScreenReadsAreCheap() async throws {
        let (alice, _) = try await populated(rooms: 6, messagesEach: 20)

        _ = alice.audienceCandidates()
        _ = alice.connections()

        let started = Date()
        for _ in 0..<50 {
            _ = alice.audienceCandidates()
            _ = alice.connections()
        }
        let each = Date().timeIntervalSince(started) / 50

        #expect(
            each < 0.002,
            """
            One pass of what `AppRootView.body` reads costs \(Int(each * 1_000_000))µs. \
            SwiftUI evaluates a body many times a second, and this pass opens every membership \
            entry in every room — ChaChaPoly plus a JSON decode each — because `roster(of:)` builds \
            a fresh opener and folds the roster on every call. Measured on the rig 2026-09-16: the \
            main thread was 100% inside this, continuously.
            """)
    }

    @Test("Nothing a screen reads re-decrypts the log on every call")
    func screenReadsAreCheap() async throws {
        let (alice, rooms) = try await populated(rooms: 6, messagesEach: 20)
        let room = try #require(rooms.first)
        let me = try #require(alice.enrolment?.identity.id)

        var reads: [(String, () -> Void)] = [
            ("roster(of:)", { _ = alice.roster(of: room) }),
            ("connections()", { _ = alice.connections() }),
            ("audienceCandidates()", { _ = alice.audienceCandidates() }),
            ("messages(in:)", { _ = alice.messages(in: room) }),
            ("transcript(in:)", { _ = alice.transcript(in: room) }),
            ("outpost()", { _ = alice.outpost() }),
            ("outpostAccess", { _ = alice.outpostAccess }),
            ("soloCheck(in:)", { _ = alice.soloCheck(in: room) }),
            ("blurb(of:)", { _ = alice.blurb(of: me) }),
            ("awaitingAdmission", { _ = alice.awaitingAdmission }),
            ("pendingJoins(in:)", { _ = alice.pendingJoins(in: room) }),
            ("lapsedInvitations(in:)", { _ = alice.lapsedInvitations(in: room) }),
            ("pendingInvitations(in:)", { _ = alice.pendingInvitations(in: room) }),
            ("reciprocalAccess(with:)", { _ = alice.reciprocalAccess(with: me) }),
            ("hiddenMessageCount(in:)", { _ = alice.hiddenMessageCount(in: room) }),
            ("devices", { _ = alice.devices }),
            ("managedTags", { _ = alice.managedTags }),
        ]

        for (_, read) in reads { read() }

        let known = ["messages(in:)": 0.005, "transcript(in:)": 0.005]

        var expensive: [String] = []
        for (name, read) in reads {
            let started = Date()
            for _ in 0..<20 { read() }
            let each = Date().timeIntervalSince(started) / 20
            if each > (known[name] ?? 0.001) {
                expensive.append("\(name) — \(Int(each * 1_000_000))µs a call")
            }
        }

        #expect(
            expensive.isEmpty,
            """
            These are read while a screen draws and cost more than a millisecond a call, which \
            means they are re-folding or re-decrypting rather than answering from the cache: \
            \(expensive.joined(separator: "; ")). SwiftUI evaluates a body many times a second and \
            a frame is 16,700µs.
            """)
        reads.removeAll()
    }
}
