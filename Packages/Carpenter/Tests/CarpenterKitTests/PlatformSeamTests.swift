import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Platform seams")
struct PlatformSeamTests {
    @Test("A test clock does not move unless the test moves it")
    func fixedClock() {
        let start = Date(timeIntervalSince1970: 1_786_635_000)
        let clock = TestClock(now: start)

        #expect(clock.now == start)
        clock.advance(by: 90)
        #expect(clock.now == start.addingTimeInterval(90))
    }

    @Test("A test random source is deterministic, so a failing case can be replayed")
    func seededRandom() {
        let a = SeededRandomSource(seed: 42).bytes(count: 32)
        let b = SeededRandomSource(seed: 42).bytes(count: 32)
        let c = SeededRandomSource(seed: 43).bytes(count: 32)

        #expect(a.count == 32)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Successive draws from one source differ")
    func randomAdvances() {
        let source = SeededRandomSource(seed: 7)
        let first = source.bytes(count: 16)
        let second = source.bytes(count: 16)
        #expect(first != second)
    }

    @Test("An in-memory keychain stores, replaces and removes by key")
    func keychain() async throws {
        let store = InMemoryKeychainStore()
        let key = KeychainKey("identity.signing")

        #expect(try await store.data(for: key) == nil)
        try await store.set(Data([1, 2, 3]), for: key, scope: .synchronized)
        #expect(try await store.data(for: key) == Data([1, 2, 3]))
        try await store.set(Data([9]), for: key, scope: .device)
        #expect(try await store.data(for: key) == Data([9]))
        #expect(await store.scope(for: key) == .device)
        try await store.remove(key)
        #expect(try await store.data(for: key) == nil)
    }
}

@Suite("In-memory mailbox")
struct InMemoryMailboxTests {
    private struct Three {
        let mailbox = InMemoryMailbox()
        let toBob: Peer
        let asBob: Peer
        let asCarol: Peer
        var alice: Pairs = Pairs(me: Identity.generate().id, hints: [:])
        var bob: Pairs = Pairs(me: Identity.generate().id, hints: [:])
        var carol: Pairs = Pairs(me: Identity.generate().id, hints: [:])
    }

    private func three() async throws -> Three {
        let alice = Identity.generate()
        let (toBob, asBob) = try peers(alice, Identity.generate())
        let (toCarol, asCarol) = try peers(alice, Identity.generate())
        var three = Three(toBob: toBob, asBob: asBob, asCarol: asCarol)
        (three.alice, three.bob) = try await link(toBob, asBob, through: three.mailbox)
        let (withCarol, carol) = try await link(toCarol, asCarol, through: three.mailbox)
        three.alice = three.alice.merging(withCarol)
        three.carol = carol
        return three
    }

    private func packet(_ body: String, to peer: Peer) -> SyncPacket {
        SyncPacket(id: PacketID(), wraps: [peer.outgoingTag(window: 1): Data()], ciphertext: Data(body.utf8))
    }

    @Test("A packet is fetchable only by the person whose space it is in, under the tag it was addressed to")
    func addressing() async throws {
        let t = try await three()
        try await t.mailbox.put(packet("sealed", to: t.toBob), to: t.toBob.them, in: t.alice)

        #expect(try await t.mailbox.fetch(from: t.toBob.me, for: [t.asBob.incomingTag(window: 1)], in: t.bob).count == 1)
        #expect(try await t.mailbox.fetch(from: t.toBob.me, for: [t.asBob.incomingTag(window: 2)], in: t.bob).isEmpty)
        #expect(
            try await t.mailbox.fetch(from: t.toBob.me, for: [t.asBob.incomingTag(window: 1)], in: t.carol).isEmpty,
            "somebody else read a packet in another person's space")
    }

    @Test("Fetching does not consume — only the sender takes a packet away")
    func fetchIsNotDestructive() async throws {
        let t = try await three()
        try await t.mailbox.put(packet("sealed", to: t.toBob), to: t.toBob.them, in: t.alice)
        let tags: Set = [t.asBob.incomingTag(window: 1)]

        #expect(try await t.mailbox.fetch(from: t.toBob.me, for: tags, in: t.bob).count == 1)
        #expect(try await t.mailbox.fetch(from: t.toBob.me, for: tags, in: t.bob).count == 1)
    }

    @Test("A receipt sits in its writer's own space; nobody but the sender takes the packet away")
    func onlyTheSenderTakesAPacketAway() async throws {
        let t = try await three()
        let sent = packet("sealed", to: t.toBob)
        try await t.mailbox.put(sent, to: t.toBob.them, in: t.alice)
        let tags: Set = [t.asBob.incomingTag(window: 1)]

        try await t.mailbox.acknowledge(
            sent.id, from: t.toBob.me, with: SealedReceipt(tag: t.asBob.incomingTag(window: 1), sealed: Data([1])), in: t.bob)
        #expect(try await t.mailbox.fetch(from: t.toBob.me, for: tags, in: t.bob).first?.receipts.count == 1)
        #expect(await t.mailbox.storedPacketCount == 1, "a recipient's receipt removed the packet")

        try await t.mailbox.withdraw(sent.id, in: t.bob)
        #expect(await t.mailbox.storedPacketCount == 1, "the recipient took the sender's packet away")

        try await t.mailbox.withdraw(sent.id, in: t.alice)
        #expect(await t.mailbox.storedPacketCount == 0)
    }

    @Test("The same receipt twice is kept once")
    func idempotentAcknowledgement() async throws {
        let t = try await three()
        let sent = packet("sealed", to: t.toBob)
        try await t.mailbox.put(sent, to: t.toBob.them, in: t.alice)

        let receipt = SealedReceipt(tag: t.asBob.incomingTag(window: 1), sealed: Data([1]))
        try await t.mailbox.acknowledge(sent.id, from: t.toBob.me, with: receipt, in: t.bob)
        try await t.mailbox.acknowledge(sent.id, from: t.toBob.me, with: receipt, in: t.bob)

        #expect(try await t.mailbox.sentPackets(in: t.alice)[sent.id]?.receipts == [receipt])
    }

    @Test("Every write is counted, so the budget in Epic 4 has something to measure")
    func writesAreInstrumented() async throws {
        let t = try await three()
        try await t.mailbox.put(packet("one", to: t.toBob), to: t.toBob.them, in: t.alice)
        try await t.mailbox.put(packet("two", to: t.toBob), to: t.toBob.them, in: t.alice)

        #expect(await t.mailbox.writeCount == 2)
    }

    @Test("A failing mailbox surfaces its error rather than silently dropping a packet")
    func failureIsVisible() async throws {
        let t = try await three()
        await t.mailbox.failNextWrite(with: .unavailable)

        await #expect(throws: MailboxError.unavailable) {
            try await t.mailbox.put(packet("sealed", to: t.toBob), to: t.toBob.them, in: t.alice)
        }
        #expect(await t.mailbox.storedPacketCount == 0)
    }
}
