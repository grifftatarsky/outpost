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

    @Test("Reading the same state twice builds the projection once")
    func readsAreCheapBetweenWrites() async throws {
        let (alice, rooms) = try await populated(rooms: 4, messagesEach: 8)
        let room = try #require(rooms.first)

        _ = alice.messages(in: room)

        let before = alice.projectionBuilds
        _ = alice.messages(in: room)
        _ = alice.transcript(in: room)
        _ = alice.roster(of: room)
        _ = alice.outpost()
        let builds = alice.projectionBuilds - before

        #expect(
            builds == 0,
            """
            four reads with no write between them rebuilt the projection \(builds) time(s). \
            A rebuild reads the whole log; a screen that reads three things should not pay for three.
            """)
    }

    @Test("Refreshing after a write rebuilds the projection once, whatever the room count")
    func refreshDoesNotScaleWithRooms() async throws {
        let (alice, rooms) = try await populated(rooms: 6, messagesEach: 4)
        let room = try #require(rooms.first)
        _ = alice.messages(in: room)

        let before = alice.projectionBuilds
        try await alice.send("one more", to: room)
        let builds = alice.projectionBuilds - before

        #expect(
            builds <= 1,
            """
            one message into a six-room account rebuilt the projection \(builds) time(s). \
            This used to grow with the number of rooms, on a path that runs every five seconds \
            while a conversation is open.
            """)
    }

    @Test("A write is still visible to the next read")
    func theCacheCannotGoStale() async throws {
        let (alice, rooms) = try await populated(rooms: 2, messagesEach: 2)
        let room = try #require(rooms.first)

        _ = alice.messages(in: room)
        try await alice.send("after the read", to: room)

        #expect(
            alice.messages(in: room).contains { $0.body == "after the read" },
            "the projection was cached and not cleared — the worst possible outcome of this change")
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
            a fresh opener and rebuilds the member list on every call. Measured on the rig 2026-09-16: the \
            main thread was 100% inside this, continuously.
            """)
    }

    @Test("Naming an author costs the same however long the log is")
    func namingDoesNotScanTheLog() {
        let viewer = ParticipantID(rawValue: WideID.of([1]))
        let author = ParticipantID(rawValue: WideID.of([2]))
        let room = RoomID()
        func entry(_ index: Int) -> RenderedEntry {
            let naming = index == 0
            let text: String = naming ? "Outie" : "message \(index)"
            let hash = WideID.of([3, UInt8(index % 256), UInt8(index / 256)])
            return RenderedEntry(
                id: EntryHash(rawValue: hash), type: naming ? .memberProfile : .post, author: author,
                device: DeviceID(rawValue: WideID.of([4])), wallTime: Date(timeIntervalSince1970: Double(index)),
                room: naming ? nil : room, content: .text(text), editedAt: nil, replyingTo: nil,
                reactions: [:])
        }
        let rendered: [RenderedEntry] = (0..<5_000).map(entry)
        let projected = Projection(viewer: viewer, rendered: rendered)
        #expect(projected.member(author).displayName == "Outie")

        let started = Date()
        for _ in 0..<500 { _ = projected.member(author) }
        let each = Date().timeIntervalSince(started) / 500

        #expect(
            each < 0.00001,
            """
            Naming one author costs \(Int(each * 1_000_000))µs over a 5,000-entry log. `member(_:)` is \
            read once per message on every screen, so it has to answer from what the projection \
            already holds, not walk the log to rebuild every name each time.
            """)
    }

    @Test("Finding one entry by its hash does not walk the log")
    func findingAnEntryDoesNotScan() {
        let viewer = ParticipantID(rawValue: WideID.of([1]))
        let rendered: [RenderedEntry] = (0..<5_000).map { index in
            RenderedEntry(
                id: EntryHash(rawValue: WideID.of([7, UInt8(index % 256), UInt8(index / 256)])), type: .post,
                author: viewer, device: DeviceID(rawValue: WideID.of([8])),
                wallTime: Date(timeIntervalSince1970: Double(index)), room: RoomID(), content: .text("\(index)"),
                editedAt: nil, replyingTo: nil, reactions: [:])
        }
        let projected = Projection(viewer: viewer, rendered: rendered)
        let newest = rendered[4_999].id
        #expect(projected.entry(newest)?.id == newest)
        #expect(projected.entry(EntryHash(rawValue: WideID.of([9]))) == nil)

        let started = Date()
        for _ in 0..<500 { _ = projected.entry(newest) }
        let each = Date().timeIntervalSince(started) / 500

        #expect(
            each < 0.00002,
            """
            Finding the newest of 5,000 entries took \(Int(each * 1_000_000))µs. The edit and \
            withdraw windows ask for a message this way, and a message still inside them is always \
            near the end of the log.
            """)
    }

    @Test("Drawing the feed does not walk the log once per post")
    func theFeedIsLinear() {
        let viewer = ParticipantID(rawValue: WideID.of([1]))
        let author = ParticipantID(rawValue: WideID.of([2]))
        func entry(_ index: Int, replyingTo target: EntryHash?) -> RenderedEntry {
            let text: String = target == nil ? "post \(index)" : "comment \(index)"
            var made = RenderedEntry(
                id: EntryHash(rawValue: WideID.of([5, UInt8(index % 256), UInt8(index / 256)])),
                type: target == nil ? .post : .comment, author: author,
                device: DeviceID(rawValue: WideID.of([6])), wallTime: Date(timeIntervalSince1970: Double(index)),
                room: nil, content: .text(text), editedAt: nil, replyingTo: target, reactions: [:])
            made.seq = UInt64(index)
            return made
        }
        let posts: [RenderedEntry] = (0..<300).map { entry($0, replyingTo: nil) }
        let comments: [RenderedEntry] = (0..<3_000).map { entry(300 + $0, replyingTo: posts[$0 % 300].id) }
        let projected = Projection(viewer: viewer, rendered: posts + comments)

        let feed = projected.feed()
        #expect(feed.count == 300)
        #expect(feed.allSatisfy { $0.commentCount == 10 })

        let took = (0..<5).map { _ in
            let started = Date()
            _ = projected.feed()
            return Date().timeIntervalSince(started)
        }.min() ?? .infinity

        #expect(
            took < 0.05,
            """
            Drawing a feed of 300 posts over 3,300 entries took \(Int(took * 1_000))ms. Each post \
            used to gather its comments by walking the whole log.
            """)
    }

    @Test("A round that brings nothing new keeps the projection it had")
    func anEmptyRoundKeepsTheProjection() async throws {
        let mailbox = InMemoryMailbox()
        let alice = session()
        let bob = session()
        for member in [alice, bob] { await member.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Kitchen")
        let invite = try await alice.invite(joinerCode: await bob.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        for _ in 0..<8 {
            for member in [alice, bob] { try await member.sync(through: mailbox) }
        }

        _ = alice.messages(in: room)
        let before = alice.projectionBuilds
        for _ in 0..<3 { try await alice.sync(through: mailbox) }
        _ = alice.messages(in: room)

        #expect(
            alice.projectionBuilds == before,
            """
            Three rounds that brought nothing new rebuilt the projection \(alice.projectionBuilds - before) \
            time(s). Every rebuild re-sorts and re-renders the whole log and tells every screen to \
            draw again.
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
            means they are rebuilding or re-decrypting rather than answering from the cache: \
            \(expensive.joined(separator: "; ")). SwiftUI evaluates a body many times a second and \
            a frame is 16,700µs.
            """)
        reads.removeAll()
    }
}
