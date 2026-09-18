import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("A message typed mid-fetch", .serialized)
@MainActor
struct ReplicaRaceTests {
    private func scratch() -> URL {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-fetch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func session(_ clock: TestClock, at directory: URL? = nil) -> AppSession {
        let root = directory ?? scratch()
        return AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(),
                log: FileLogStore(url: root.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: root.appending(path: "state.json"))
            ),
            clock: clock
        )
    }

    private actor SlowFetchMailbox: Mailbox {
        private let inner = InMemoryMailbox()
        private var duringFetch: (@Sendable () async -> Void)?

        func onFetch(_ work: @escaping @Sendable () async -> Void) { duringFetch = work }

        func put(_ packet: SyncPacket) async throws { try await inner.put(packet) }

        func fetch(for tags: Set<RecipientTag>) async throws -> [SyncPacket] {
            if let duringFetch { self.duringFetch = nil; await duringFetch() }
            return try await inner.fetch(for: tags)
        }

        func acknowledge(_ id: PacketID, by tags: Set<RecipientTag>) async throws {
            try await inner.acknowledge(id, by: tags)
        }
        func pendingDeliveries() async throws -> [PacketID: Set<RecipientTag>] {
            try await inner.pendingDeliveries()
        }
        func ring(_ bell: MessageBell) async throws { try await inner.ring(bell) }
    }

    private func pair(_ clock: TestClock, _ mailbox: any Mailbox, aliceAt: URL? = nil) async throws
        -> (alice: AppSession, bob: AppSession, room: RoomID)
    {
        let alice = session(clock, at: aliceAt)
        let bob = session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, room)
    }

    @Test("A message typed while a round is fetching does not vanish from the sender's own screen")
    func appendedMidFetchSurvives() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = SlowFetchMailbox()
        let (alice, bob, room) = try await pair(clock, mailbox)

        await mailbox.onFetch { @Sendable in
            await MainActor.run { Task { try? await alice.send("typed while fetching", to: room) } }
            try? await Task.sleep(for: .milliseconds(60))
        }
        try await alice.sync(through: mailbox)

        #expect(
            alice.messages(in: room).contains { $0.body == "typed while fetching" },
            "the round overwrote the replica with a copy taken before the message was written")

        for _ in 0..<3 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        #expect(
            bob.messages(in: room).contains { $0.body == "typed while fetching" },
            "the message was erased from memory, so it was never offered to the mailbox either")
    }

    @Test("The message was never lost from disk, which is why it reappeared later")
    func theEntryWasAlwaysOnDisk() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = SlowFetchMailbox()
        let directory = scratch()
        let keychain = InMemoryKeychainStore()
        let storage = {
            SessionStorage(
                keychain: keychain,
                log: FileLogStore(url: directory.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json")))
        }

        let alice = AppSession(storage: storage(), clock: clock)
        let bob = session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        await mailbox.onFetch { @Sendable in
            await MainActor.run { Task { try? await alice.send("survives a relaunch", to: room) } }
            try? await Task.sleep(for: .milliseconds(60))
        }
        try await alice.sync(through: mailbox)

        let relaunched = AppSession(storage: storage(), clock: clock)
        await relaunched.load()
        #expect(relaunched.messages(in: room).contains { $0.body == "survives a relaunch" })
    }
}

@Suite("Acknowledging a packet")
struct AcknowledgementTests {
    @Test("A packet whose entries would not verify is left for the next round")
    func rejectedEntriesHoldThePacket() throws {
        let stranger = try Identity.generate()
        let device = DeviceKeys.generate()
        let chain = EpochChain.create(room: RoomID())

        let entry = try Entry.append(
            to: nil, author: stranger.id, device: device, clock: VectorClock(),
            wallTime: TestSession.now, room: chain.chain.room, payload: try Payload.post("hello"),
            at: .initial, sealedWith: chain.chain)

        let packet = SyncSession.CollectedPackets(
            tags: [RecipientTag(rawValue: Data([1]))],
            packets: [
                SyncSession.CollectedPackets.Opened(
                    id: PacketID(),
                    delivery: SyncEngine.Delivery(
                        entries: [entry], certificates: [], revocations: [], grants: []))
            ])

        var replica = Replica()
        let (report, settled) = SyncSession.integrate(packet, into: &replica)

        #expect(report.entriesRejected == 1)
        #expect(settled.isEmpty, "a packet was acknowledged after refusing what was in it")
    }

    @Test("A packet that landed whole is acknowledged")
    func acceptedEntriesSettleThePacket() throws {
        let author = try Identity.generate()
        let device = DeviceKeys.generate()
        let chain = EpochChain.create(room: RoomID())
        let certificate = try DeviceCertificate.issue(
            for: device.publicKey, by: author, at: .distantPast)

        let entry = try Entry.append(
            to: nil, author: author.id, device: device, clock: VectorClock(),
            wallTime: TestSession.now, room: chain.chain.room, payload: try Payload.post("hello"),
            at: .initial, sealedWith: chain.chain)

        let packet = SyncSession.CollectedPackets(
            tags: [RecipientTag(rawValue: Data([1]))],
            packets: [
                SyncSession.CollectedPackets.Opened(
                    id: PacketID(),
                    delivery: SyncEngine.Delivery(
                        entries: [entry], certificates: [certificate], revocations: [], grants: []))
            ])

        var replica = Replica()
        replica.introduce(author.publicKeys)
        let (report, settled) = SyncSession.integrate(packet, into: &replica)

        #expect(report.entriesReceived == 1)
        #expect(settled.count == 1)
    }

    @Test("A packet whose certificate was refused is left for the next round")
    func rejectedCertificateHoldsThePacket() throws {
        let known = try Identity.generate()
        let knownDevice = DeviceKeys.generate()
        let chain = EpochChain.create(room: RoomID())

        let entry = try Entry.append(
            to: nil, author: known.id, device: knownDevice, clock: VectorClock(),
            wallTime: TestSession.now, room: chain.chain.room, payload: try Payload.post("hello"),
            at: .initial, sealedWith: chain.chain)

        let stranger = try Identity.generate()
        let strangerCertificate = try DeviceCertificate.issue(
            for: DeviceKeys.generate().publicKey, by: stranger, at: .distantPast)

        let packet = SyncSession.CollectedPackets(
            tags: [RecipientTag(rawValue: Data([1]))],
            packets: [
                SyncSession.CollectedPackets.Opened(
                    id: PacketID(),
                    delivery: SyncEngine.Delivery(
                        entries: [entry],
                        certificates: [
                            try DeviceCertificate.issue(
                                for: knownDevice.publicKey, by: known, at: .distantPast),
                            strangerCertificate,
                        ],
                        revocations: [], grants: []))
            ])

        var replica = Replica()
        replica.introduce(known.publicKeys)
        let (report, settled) = SyncSession.integrate(packet, into: &replica)

        #expect(report.entriesReceived == 1, "the good entry did not land")
        #expect(report.entriesRejected == 0, "a refused certificate was counted as a bad entry")
        #expect(report.credentialsRejected == 1, "the refused certificate was not counted anywhere")
        #expect(
            settled.isEmpty,
            "the packet was acknowledged with a certificate still unlanded, which deletes the only copy of it")
    }

    @Test("A packet whose certificates all landed is still acknowledged")
    func acceptedCertificatesStillSettle() throws {
        let known = try Identity.generate()
        let device = DeviceKeys.generate()
        let chain = EpochChain.create(room: RoomID())

        let entry = try Entry.append(
            to: nil, author: known.id, device: device, clock: VectorClock(),
            wallTime: TestSession.now, room: chain.chain.room, payload: try Payload.post("hello"),
            at: .initial, sealedWith: chain.chain)

        let packet = SyncSession.CollectedPackets(
            tags: [RecipientTag(rawValue: Data([1]))],
            packets: [
                SyncSession.CollectedPackets.Opened(
                    id: PacketID(),
                    delivery: SyncEngine.Delivery(
                        entries: [entry],
                        certificates: [
                            try DeviceCertificate.issue(
                                for: device.publicKey, by: known, at: .distantPast)
                        ],
                        revocations: [], grants: []))
            ])

        var replica = Replica()
        replica.introduce(known.publicKeys)
        let (_, settled) = SyncSession.integrate(packet, into: &replica)

        #expect(settled.count == 1, "a clean packet stopped being acknowledged")
    }
}
