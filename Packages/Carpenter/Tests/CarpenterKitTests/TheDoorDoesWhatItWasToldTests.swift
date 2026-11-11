@testable import CarpenterApp
import CarpenterKitTesting
import Foundation
import Synchronization
import Testing

@testable import CarpenterKit

@Suite("The fake iCloud and keychain do what they were told, and only that", .serialized, .tags(.sync))
struct TheDoorDoesWhatItWasToldTests {
    private struct Line {
        let cloud: InMemoryMailbox
        let clock: TestClock
        let alice: HookedMailbox
        let bob: HookedMailbox
        let toBob: Peer
        let asBob: Peer
        let alicePairs: Pairs
        let bobPairs: Pairs

        var tag: RecipientTag { toBob.outgoingTag(window: 1) }
        var bobsTag: RecipientTag { asBob.incomingTag(window: 1) }

        func packet(_ size: Int = 16) -> SyncPacket {
            SyncPacket(wraps: [tag: Data(count: 32)], ciphertext: Data(count: size))
        }

        func put(_ packet: SyncPacket) async throws {
            try await alice.put(packet, to: toBob.them, in: alicePairs)
        }

        func collected() async throws -> [SyncPacket] {
            try await bob.fetch(from: toBob.me, for: [bobsTag], in: bobPairs)
        }
    }

    private func line() async throws -> Line {
        let clock = TestClock(now: TestSession.now)
        let cloud = InMemoryMailbox(clock: clock)
        let (toBob, asBob) = try peers(Identity.generate(), Identity.generate())
        let (alicePairs, bobPairs) = try await link(toBob, asBob, through: cloud)
        return Line(
            cloud: cloud, clock: clock, alice: HookedMailbox(inner: cloud), bob: HookedMailbox(inner: cloud),
            toBob: toBob, asBob: asBob, alicePairs: alicePairs, bobPairs: bobPairs)
    }

    @Test("A failed call fails once on its own door, and the next one goes")
    func aFailedCallFailsOnce() async throws {
        let l = try await line()
        await l.alice.fail(.put)
        await #expect(throws: MailboxError.self) { try await l.put(l.packet()) }
        #expect(await l.cloud.storedPacketCount == 0, "a write that failed was stored")
        try await l.put(l.packet())
        #expect(await l.cloud.storedPacketCount == 1, "the fault fired twice")
        _ = try await l.collected()
        #expect(await l.bob.calls.map(\.call) == [.fetch], "the other door saw the fault or missed its own call")
    }

    @Test("A write whose answer is lost lands and still throws")
    func aLostAnswerStillLands() async throws {
        let l = try await line()
        await l.alice.fail(.put, landing: true)
        await #expect(throws: MailboxError.self) { try await l.put(l.packet()) }
        #expect(await l.cloud.storedPacketCount == 1, "the write did not land")
    }

    @Test("A door that stops answering after some calls throws on every call after them until it relents")
    func aDoorStopsAnsweringAndRelents() async throws {
        let l = try await line()
        await l.alice.stopAnswering(after: 1)
        try await l.put(l.packet())
        await #expect(throws: MailboxError.self) { try await l.put(l.packet()) }
        await #expect(throws: MailboxError.self) { _ = try await l.alice.sentPackets(in: l.alicePairs) }
        _ = try await l.collected()
        await l.alice.relent()
        try await l.put(l.packet())
        #expect(await l.cloud.storedPacketCount == 2)
    }

    @Test("A step set for a call runs at that call and no other")
    func aStepRunsAtItsCall() async throws {
        let l = try await line()
        let ranAt = Mutex<[Int]>([])
        let door = l.alice
        await door.before(call: 2) {
            let count = await door.calls.count
            ranAt.withLock { $0.append(count) }
        }
        for _ in 0..<3 { try await l.put(l.packet()) }
        #expect(ranAt.withLock { $0 } == [2])
    }

    @Test("A door that hangs up inside a step fails the call it is in")
    func hangingUpFailsTheCallInProgress() async throws {
        let l = try await line()
        let door = l.alice
        await door.before(call: 1) { await door.hangUp() }
        await #expect(throws: MailboxError.self) { try await l.put(l.packet()) }
        #expect(await l.cloud.storedPacketCount == 0)
    }

    @Test("A skipped packet stays out of every read until the peer's space changes, as an index left unread does")
    func aSkippedPacketStaysOutUntilThePeerWritesAgain() async throws {
        let l = try await line()
        let skipped = l.packet()
        try await l.put(skipped)
        try await l.put(l.packet())
        await l.bob.skip(skipped.id)
        #expect(try await l.collected().map(\.id).contains(skipped.id) == false)
        #expect(try await l.collected().count == 1, "a skipped packet came back with nothing written")
        try await l.put(l.packet())
        #expect(try await l.collected().count == 3, "a write to the space did not bring the skipped packet back")
    }

    @Test("A held view still shows this device what it wrote itself")
    func aHeldViewKeepsItsOwnWrites() async throws {
        let l = try await line()
        await l.alice.holdView()
        let packet = l.packet()
        try await l.put(packet)
        #expect(try await l.alice.sentPackets(in: l.alicePairs)[packet.id] != nil, "a held view lost its own write")
    }

    @Test("A held view does not see what was stored after it, and a fresh one does")
    func aHeldViewIsStale() async throws {
        let l = try await line()
        try await l.put(l.packet())
        await l.bob.holdView()
        try await l.put(l.packet())
        #expect(try await l.collected().count == 1, "the held view saw a write made after it")
        await l.bob.refreshView()
        #expect(try await l.collected().count == 2)
    }

    @Test("A packet's stored time is when it was last stored, as a record's modification date is")
    func aRewrittenPacketIsDatedByItsRewrite() async throws {
        let l = try await line()
        let packet = l.packet()
        try await l.put(packet)
        let first = try #require(try await l.collected().first?.storedAt)
        l.clock.advance(by: 3_600)
        await l.cloud.tamper(packet: packet.id) { _ in }
        let again = try #require(try await l.collected().first?.storedAt)
        #expect(again.timeIntervalSince(first) >= 3_600, "a rewritten packet kept its first-stored date")
    }

    @Test("Packets stored in one instant come back in an order drawn from the seed, all of them")
    func packetsFromOneInstantComeBackInTheSeedsOrder() async throws {
        let l = try await line()
        var written: [PacketID] = []
        for _ in 0..<8 {
            let packet = l.packet()
            written.append(packet.id)
            try await l.put(packet)
        }
        var orders: Set<[PacketID]> = []
        for seed in 0..<6 {
            await l.cloud.sameInstant(within: 1, seed: UInt64(seed))
            let order = try await l.collected().map(\.id)
            #expect(Set(order) == Set(written), "a packet went missing in a shuffled read")
            orders.insert(order)
        }
        #expect(orders.count > 1, "every seed gave the same order")
    }

    @Test("A relay fails one refresh and one send, each once")
    func aRelayFailsOneSendAndOneRefresh() async throws {
        let relay = InMemoryEntrySync.Relay(announces: false)
        let engine = InMemoryEntrySync(relay: relay, as: "phone")
        await relay.failNextSend(storing: 0)
        await relay.failNextRefresh()
        #expect(await relay.failuresPending == 2)
        await #expect(throws: InMemoryEntrySync.Relay.Refused.self) { try await engine.refresh() }
        try await engine.refresh()
        #expect(await relay.failuresPending == 1)
        await #expect(throws: InMemoryEntrySync.Relay.Refused.self) { try await engine.send([], deleting: []) }
        #expect(await relay.failuresPending == 0)
    }

    @Test("A relay that hands a change over once does not hand it over again, even to a relaunched device")
    @MainActor
    func aRelayHandsAChangeOverOnce() async throws {
        let g = try await Gathering.of("Bob")
        let phone = try #require(g["Bob"].enrolment?.device.id)
        try await g.secondDevice("Bob's tablet", of: "Bob")
        let before = await g.relay(of: "Bob").names(from: phone).count
        try #require(before > 0, "precondition: Bob's phone wrote to device sync")

        await g["Bob's tablet"].refreshDeviceSync()
        try await g.quiesce()
        let heard = Mutex(0)
        let engine = InMemoryEntrySync(relay: g.relay(of: "Bob"), as: "Bob's tablet")
        await engine.onIncoming { record in if record.name.writer == phone { heard.withLock { $0 += 1 } } }
        try await engine.refresh()
        #expect(heard.withLock { $0 } == 0, "a relaunched tablet was handed what it had already been handed")

        let fresh = InMemoryEntrySync(relay: g.relay(of: "Bob"), as: "somebody new")
        await fresh.onIncoming { record in if record.name.writer == phone { heard.withLock { $0 += 1 } } }
        try await fresh.refresh()
        #expect(heard.withLock { $0 } > 0, "a device never handed anything heard nothing")
    }

    @Test("A relay on iCloud's clock stamps records at that clock")
    @MainActor
    func aRelayStampsWithICloudsClock() async throws {
        let g = try await Gathering.of("Bob")
        let phone = try #require(g["Bob"].enrolment?.device.id)
        let name = try #require(await g.relay(of: "Bob").names(from: phone).first)
        let created = try #require(await g.relay(of: "Bob").created(name))
        #expect(abs(created.timeIntervalSince(g.iCloud.now)) < 1, "the relay's clock is not iCloud's")
    }

    @Test("A copy of a keychain keeps this device's items and shares the synchronized ones")
    func aKeychainCopyKeepsWhatTheDeviceHeld() async throws {
        let keychain = InMemoryKeychainStore()
        let mine = KeychainKey("device-only")
        let shared = KeychainKey("synchronized")
        try await keychain.set(Data([1]), for: mine, scope: .device)
        try await keychain.set(Data([2]), for: shared, scope: .synchronized)
        let copy = await keychain.copy()
        try await keychain.set(Data([3]), for: mine, scope: .device)
        #expect(try await copy.data(for: mine) == Data([1]), "the copy follows the original's device items")
        #expect(try await copy.data(for: shared) == Data([2]))
    }
}
