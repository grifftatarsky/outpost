import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Sync packets")
struct SyncEngineTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func pair() throws -> (Peer, Peer) {
        let a = Identity.generate()
        let b = Identity.generate()
        return (
            Peer(
                secret: try PairwiseSecret.derive(mine: a, theirs: b.publicKeys),
                them: b.id, me: a.id),
            Peer(
                secret: try PairwiseSecret.derive(mine: b, theirs: a.publicKeys),
                them: a.id, me: b.id)
        )
    }

    @Test("A packet round-trips for the peer it is addressed to")
    func roundTrip() throws {
        var alice = Author()
        let (mine, theirs) = try pair()
        let entries = [
            try alice.post("one", at: start),
            try alice.post("two", at: start.addingTimeInterval(1)),
        ]

        let packet = try SyncEngine.pack(entries, for: [mine], window: 7)

        #expect(try SyncEngine.unpack(packet, as: theirs, window: 7).entries == entries)
    }

    @Test("A packet is one record however many entries it carries")
    func batching() throws {
        var alice = Author()
        let (mine, theirs) = try pair()
        let entries = try (0..<50).map {
            try alice.post("entry \($0)", at: start.addingTimeInterval(Double($0)))
        }

        let packet = try SyncEngine.pack(entries, for: [mine], window: 7)

        #expect(packet.wraps.count == 1)
        #expect(try SyncEngine.unpack(packet, as: theirs, window: 7).entries.count == 50)
    }

    @Test("One packet serves several recipients, each opening only their own wrap")
    func multipleRecipients() throws {
        var alice = Author()
        let (bob, bobSees) = try pair()
        let (carol, carolSees) = try pair()
        let entries = [try alice.post("hello", at: start)]

        let packet = try SyncEngine.pack(entries, for: [bob, carol], window: 7)

        #expect(packet.wraps.count == 2)
        #expect(try SyncEngine.unpack(packet, as: bobSees, window: 7).entries == entries)
        #expect(try SyncEngine.unpack(packet, as: carolSees, window: 7).entries == entries)
    }

    @Test("Someone the packet is not addressed to cannot even find a wrap to try")
    func outsidersAreNotAddressed() throws {
        var alice = Author()
        let (mine, _) = try pair()
        let (outsider, _) = try pair()

        let packet = try SyncEngine.pack([try alice.post("hello", at: start)], for: [mine], window: 7)

        #expect(throws: SyncError.notAddressedToUs) {
            try SyncEngine.unpack(packet, as: outsider, window: 7)
        }
    }

    @Test("The address changes with the rotation window")
    func addressRotates() throws {
        var alice = Author()
        let (mine, theirs) = try pair()

        let packet = try SyncEngine.pack([try alice.post("hello", at: start)], for: [mine], window: 7)

        #expect(throws: SyncError.notAddressedToUs) {
            try SyncEngine.unpack(packet, as: theirs, window: 8)
        }
    }

    @Test("Relabelling a packet with another identifier makes it unopenable")
    func wrapsAreBoundToTheirPacket() throws {
        var alice = Author()
        let (mine, theirs) = try pair()

        let packet = try SyncEngine.pack([try alice.post("real", at: start)], for: [mine], window: 7)
        let relabelled = SyncPacket(
            id: PacketID(), wraps: packet.wraps, ciphertext: packet.ciphertext)

        #expect(try SyncEngine.unpack(packet, as: theirs, window: 7).entries.count == 1)
        #expect(throws: (any Error).self) {
            try SyncEngine.unpack(relabelled, as: theirs, window: 7)
        }
    }

    @Test("The packet reveals nothing about what it carries")
    func packetIsOpaque() throws {
        var alice = Author()
        let (mine, _) = try pair()
        let entries = [try alice.post("the mooring mast drawings", at: start)]

        let packet = try SyncEngine.pack(entries, for: [mine], window: 7)
        let wire = try JSONEncoder().encode(packet)

        #expect(!wire.contains(Data("mooring".utf8)))
        #expect(!packet.ciphertext.contains(alice.identity.id.rawValue))
    }
}

@Suite("Write budget")
struct WriteBudgetTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    @Test("Writes count against the ceiling")
    func counting() throws {
        var budget = WriteBudget(ceiling: 3, startingAt: start)

        try budget.consume(1, at: start)
        try budget.consume(1, at: start)

        #expect(budget.used == 2)
        #expect(budget.remaining == 1)
        #expect(!budget.isExhausted)
    }

    @Test("Exceeding the ceiling is refused, not logged")
    func refusal() throws {
        var budget = WriteBudget(ceiling: 2, startingAt: start)
        try budget.consume(2, at: start)

        #expect(budget.isExhausted)
        #expect(throws: MailboxError.budgetExhausted) { try budget.consume(1, at: start) }
    }

    @Test("The allowance returns when the window rolls over")
    func windowRollover() throws {
        var budget = WriteBudget(ceiling: 2, window: 3_600, startingAt: start)
        try budget.consume(2, at: start)

        #expect(throws: MailboxError.budgetExhausted) { try budget.consume(1, at: start) }
        try budget.consume(1, at: start.addingTimeInterval(3_600))
        #expect(budget.used == 1)
    }

    @Test("Usage is reportable as a fraction, for the readout Open Question 2 needs")
    func instrumentation() throws {
        var budget = WriteBudget(ceiling: 4, startingAt: start)
        try budget.consume(1, at: start)

        #expect(budget.fractionUsed == 0.25)
    }

    @Test("A budgeted mailbox refuses the write rather than passing it on")
    func enforcementAtTheTransport() async throws {
        let inner = InMemoryMailbox()
        let mailbox = BudgetedMailbox(
            wrapping: inner, budget: WriteBudget(ceiling: 1, startingAt: start),
            clock: TestClock(now: start))

        let packet = SyncPacket(
            wraps: [RecipientTag(rawValue: Data([1])): Data()], ciphertext: Data())

        try await mailbox.put(packet)
        await #expect(throws: MailboxError.budgetExhausted) { try await mailbox.put(packet) }

        #expect(await inner.writeCount == 1)
    }

    @Test("A write that failed does not spend the allowance")
    func failedWritesAreRefunded() async throws {
        let inner = InMemoryMailbox()
        await inner.failNextWrite(with: .unavailable)
        let mailbox = BudgetedMailbox(
            wrapping: inner, budget: WriteBudget(ceiling: 1, startingAt: start),
            clock: TestClock(now: start))

        let packet = SyncPacket(
            wraps: [RecipientTag(rawValue: Data([1])): Data()], ciphertext: Data())

        await #expect(throws: MailboxError.unavailable) { try await mailbox.put(packet) }
        try await mailbox.put(packet)

        #expect(await mailbox.budget.used == 1)
    }
}

@Suite("Two members converge over a mailbox")
struct MailboxConvergenceTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private struct Party {
        var author: Author
        var replica: Replica
        let peer: Peer
    }

    private func meeting() throws -> (Party, Party) {
        var alice = Author()
        var bob = Author(chain: alice.chain)

        let toBob = Peer(
            secret: try PairwiseSecret.derive(mine: alice.identity, theirs: bob.identity.publicKeys),
            them: bob.identity.id, me: alice.identity.id)
        let toAlice = Peer(
            secret: try PairwiseSecret.derive(mine: bob.identity, theirs: alice.identity.publicKeys),
            them: alice.identity.id, me: bob.identity.id)

        var aliceReplica = Replica()
        try aliceReplica.meet(alice)
        try aliceReplica.meet(bob)

        var bobReplica = Replica()
        try bobReplica.meet(alice)
        try bobReplica.meet(bob)

        return (
            Party(author: alice, replica: aliceReplica, peer: toBob),
            Party(author: bob, replica: bobReplica, peer: toAlice)
        )
    }

    @Test("What one member writes, the other reads and renders identically")
    func converges() async throws {
        let mailbox = InMemoryMailbox()
        let session = SyncSession(mailbox: mailbox, clock: TestClock(now: start))
        var (alice, bob) = try meeting()

        let entries = [
            try alice.author.post("hydrogen, obviously", at: start),
            try alice.author.post("helium coward", at: start.addingTimeInterval(1)),
        ]
        for entry in entries { try alice.replica.integrate(entry) }

        let sent = try await session.send(entries, to: [alice.peer], at: start)
        let got = try await session.receive(as: bob.peer, into: &bob.replica, at: start)

        #expect(sent.packetsWritten == 1)
        #expect(sent.entriesSent == 2)
        #expect(got.entriesReceived == 2)
        #expect(got.entriesRejected == 0)

        #expect(
            Fold.render(bob.replica.ordered(), using: bob.author.chain)
                == Fold.render(alice.replica.ordered(), using: alice.author.chain))
    }

    @Test("Syncing again changes nothing and costs no writes")
    func repeatedSyncIsIdempotent() async throws {
        let mailbox = InMemoryMailbox()
        let session = SyncSession(mailbox: mailbox, clock: TestClock(now: start))
        var (alice, bob) = try meeting()

        let entries = [try alice.author.post("once", at: start)]
        for entry in entries { try alice.replica.integrate(entry) }

        _ = try await session.send(entries, to: [alice.peer], at: start)
        _ = try await session.receive(as: bob.peer, into: &bob.replica, at: start)
        let before = Fold.render(bob.replica.ordered(), using: bob.author.chain)

        let second = try await session.receive(as: bob.peer, into: &bob.replica, at: start)

        #expect(second.packetsFetched == 0)
        #expect(Fold.render(bob.replica.ordered(), using: bob.author.chain) == before)
        #expect(await mailbox.writeCount == 1)
    }

    @Test("A packet is deleted once every recipient has acknowledged it")
    func acknowledgementDeletes() async throws {
        let mailbox = InMemoryMailbox()
        let session = SyncSession(mailbox: mailbox, clock: TestClock(now: start))
        var (alice, bob) = try meeting()

        let entries = [try alice.author.post("hello", at: start)]
        for entry in entries { try alice.replica.integrate(entry) }
        _ = try await session.send(entries, to: [alice.peer], at: start)

        #expect(await mailbox.storedPacketCount == 1)
        _ = try await session.receive(as: bob.peer, into: &bob.replica, at: start)
        #expect(await mailbox.storedPacketCount == 0)
    }

    @Test("A forged entry inside a packet is rejected without losing the rest")
    func forgedEntriesAreRejected() async throws {
        let mailbox = InMemoryMailbox()
        let session = SyncSession(mailbox: mailbox, clock: TestClock(now: start))
        var (alice, bob) = try meeting()

        let honest = try alice.author.post("real", at: start)
        let genuine = try alice.author.post("also real", at: start.addingTimeInterval(1))
        let forged = Entry(
            author: honest.author, device: honest.device, seq: 99, previous: honest.previous,
            clock: honest.clock, wallTime: honest.wallTime, room: honest.room,
            payload: honest.payload, signature: honest.signature)

        _ = try await session.send([honest, forged, genuine], to: [alice.peer], at: start)
        let got = try await session.receive(as: bob.peer, into: &bob.replica, at: start)

        #expect(got.entriesReceived == 2)
        #expect(got.entriesRejected == 1)
    }

    @Test("Sending nothing writes nothing")
    func emptySyncCostsNothing() async throws {
        let mailbox = InMemoryMailbox()
        let session = SyncSession(mailbox: mailbox, clock: TestClock(now: start))
        let (alice, _) = try meeting()

        let report = try await session.send([], to: [alice.peer], at: start)

        #expect(report.packetsWritten == 0)
        #expect(!report.didAnything)
        #expect(await mailbox.writeCount == 0)
    }

    @Test("Fifty messages in one sync is still one write")
    func batchingHoldsEndToEnd() async throws {
        let mailbox = InMemoryMailbox()
        let session = SyncSession(mailbox: mailbox, clock: TestClock(now: start))
        var (alice, bob) = try meeting()

        let entries = try (0..<50).map {
            try alice.author.post("entry \($0)", at: start.addingTimeInterval(Double($0)))
        }
        for entry in entries { try alice.replica.integrate(entry) }

        _ = try await session.send(entries, to: [alice.peer], at: start)
        let got = try await session.receive(as: bob.peer, into: &bob.replica, at: start)

        #expect(await mailbox.writeCount == 1)
        #expect(got.entriesReceived == 50)
    }
}

@Suite("File mailbox")
struct FileMailboxTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func scratch() -> URL {
        URL.temporaryDirectory.appending(path: "carpenter-mailbox-\(UUID().uuidString)")
    }

    private func pair() throws -> (Peer, Peer) {
        let a = Identity.generate()
        let b = Identity.generate()
        return (
            Peer(
                secret: try PairwiseSecret.derive(mine: a, theirs: b.publicKeys),
                them: b.id, me: a.id),
            Peer(
                secret: try PairwiseSecret.derive(mine: b, theirs: a.publicKeys),
                them: a.id, me: b.id)
        )
    }

    @Test("A packet written by one side is collected by the other")
    func delivery() async throws {
        var alice = Author()
        let (mine, theirs) = try pair()
        let mailbox = FileMailbox(directory: scratch())

        let entries = [try alice.post("evening", at: start)]
        try await mailbox.put(SyncEngine.pack(entries, for: [mine], window: 7))

        let collected = try await mailbox.fetch(for: theirs.incomingTag(window: 7))
        #expect(collected.count == 1)
        #expect(try SyncEngine.unpack(collected[0], as: theirs, window: 7).entries == entries)
    }

    @Test("The sender does not collect its own packet")
    func senderDoesNotCollectItsOwn() async throws {
        var alice = Author()
        let (mine, _) = try pair()
        let mailbox = FileMailbox(directory: scratch())

        try await mailbox.put(SyncEngine.pack([try alice.post("hello", at: start)], for: [mine], window: 7))

        #expect(try await mailbox.fetch(for: mine.incomingTag(window: 7)).isEmpty)
    }

    @Test("A packet survives until everybody has collected it")
    func deletedOnlyWhenNobodyIsWaiting() async throws {
        var alice = Author()
        let a = Identity.generate()
        let b = Identity.generate()
        let c = Identity.generate()
        let toB = Peer(
            secret: try PairwiseSecret.derive(mine: a, theirs: b.publicKeys), them: b.id, me: a.id)
        let toC = Peer(
            secret: try PairwiseSecret.derive(mine: a, theirs: c.publicKeys), them: c.id, me: a.id)
        let asB = Peer(
            secret: try PairwiseSecret.derive(mine: b, theirs: a.publicKeys), them: a.id, me: b.id)
        let asC = Peer(
            secret: try PairwiseSecret.derive(mine: c, theirs: a.publicKeys), them: a.id, me: c.id)

        let mailbox = FileMailbox(directory: scratch())
        let packet = try SyncEngine.pack(
            [try alice.post("both of you", at: start)], for: [toB, toC], window: 7)
        try await mailbox.put(packet)

        try await mailbox.acknowledge(packet.id, by: asB.incomingTag(window: 7))
        #expect(try await mailbox.pendingCount() == 1)
        #expect(try await mailbox.fetch(for: asC.incomingTag(window: 7)).count == 1)

        try await mailbox.acknowledge(packet.id, by: asC.incomingTag(window: 7))
        #expect(try await mailbox.pendingCount() == 0)
    }

    @Test("Packets outlive the process that wrote them")
    func survivesRelaunch() async throws {
        var alice = Author()
        let (mine, theirs) = try pair()
        let directory = scratch()

        try await FileMailbox(directory: directory).put(
            SyncEngine.pack([try alice.post("still here", at: start)], for: [mine], window: 7))

        let reopened = FileMailbox(directory: directory)
        #expect(try await reopened.fetch(for: theirs.incomingTag(window: 7)).count == 1)
    }

    @Test("Acknowledging something that is not there is an error, not a crash")
    func unknownPacket() async throws {
        let mailbox = FileMailbox(directory: scratch())
        await #expect(throws: MailboxError.unknownPacket) {
            try await mailbox.acknowledge(PacketID(), by: RecipientTag(rawValue: Data([1])))
        }
    }
}
