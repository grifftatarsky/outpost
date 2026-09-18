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
    private let cassilda = RecipientTag(rawValue: Data("cassilda".utf8))
    private let hastur = RecipientTag(rawValue: Data("hastur".utf8))

    private func packet(_ body: String, to recipients: Set<RecipientTag>) -> SyncPacket {
        SyncPacket(
            id: PacketID(),
            wraps: Dictionary(uniqueKeysWithValues: recipients.map { ($0, Data()) }),
            ciphertext: Data(body.utf8))
    }

    @Test("A packet is fetchable only by the tags it was addressed to")
    func addressing() async throws {
        let mailbox = InMemoryMailbox()
        try await mailbox.put(packet("sealed", to: [cassilda]))

        #expect(try await mailbox.fetch(for: cassilda).count == 1)
        #expect(try await mailbox.fetch(for: hastur).isEmpty)
    }

    @Test("Fetching does not consume — only acknowledgement does")
    func fetchIsNotDestructive() async throws {
        let mailbox = InMemoryMailbox()
        try await mailbox.put(packet("sealed", to: [cassilda]))

        #expect(try await mailbox.fetch(for: cassilda).count == 1)
        #expect(try await mailbox.fetch(for: cassilda).count == 1)
    }

    @Test("A packet survives until every recipient has acknowledged it")
    func deletesOnlyWhenFullyAcknowledged() async throws {
        let mailbox = InMemoryMailbox()
        let sent = packet("sealed", to: [cassilda, hastur])
        try await mailbox.put(sent)

        try await mailbox.acknowledge(sent.id, by: cassilda)
        #expect(try await mailbox.fetch(for: cassilda).isEmpty)
        #expect(try await mailbox.fetch(for: hastur).count == 1)
        #expect(await mailbox.storedPacketCount == 1)

        try await mailbox.acknowledge(sent.id, by: hastur)
        #expect(await mailbox.storedPacketCount == 0)
    }

    @Test("Acknowledging twice is not an error and does not double-count")
    func idempotentAcknowledgement() async throws {
        let mailbox = InMemoryMailbox()
        let sent = packet("sealed", to: [cassilda, hastur])
        try await mailbox.put(sent)

        try await mailbox.acknowledge(sent.id, by: cassilda)
        try await mailbox.acknowledge(sent.id, by: cassilda)

        #expect(await mailbox.storedPacketCount == 1)
    }

    @Test("Every write is counted, so the budget in Epic 4 has something to measure")
    func writesAreInstrumented() async throws {
        let mailbox = InMemoryMailbox()
        try await mailbox.put(packet("one", to: [cassilda]))
        try await mailbox.put(packet("two", to: [cassilda]))

        #expect(await mailbox.writeCount == 2)
    }

    @Test("A failing mailbox surfaces its error rather than silently dropping a packet")
    func failureIsVisible() async throws {
        let mailbox = InMemoryMailbox()
        await mailbox.failNextWrite(with: .unavailable)

        await #expect(throws: MailboxError.unavailable) {
            try await mailbox.put(packet("sealed", to: [cassilda]))
        }
        #expect(await mailbox.storedPacketCount == 0)
    }
}
