@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A packet of strangers stops nobody", .serialized)
struct APacketOfStrangersTests {
    private func strangers(_ count: Int) throws -> (identities: [IdentityPublicKeys], certificates: [DeviceCertificate]) {
        var identities: [IdentityPublicKeys] = []
        var certificates: [DeviceCertificate] = []
        for _ in 0..<count {
            let identity = Identity.generate()
            identities.append(identity.publicKeys)
            certificates.append(
                try DeviceCertificate.recovered(for: DeviceKeys.generate(), by: identity, at: TestSession.now))
        }
        return (identities, certificates)
    }

    private func writePacket(
        from sender: AppSession, to receiver: AppSession, through mailbox: InMemoryMailbox,
        identities: [IdentityPublicKeys], certificates: [DeviceCertificate], entries: [Entry] = []
    ) async throws {
        let receiverID = try #require(receiver.enrolment?.identity.id)
        let pairs = try #require(sender.pairs())
        let peer = try #require(sender.peers().first { $0.them == receiverID })
        let packet = try SyncEngine.pack(
            entries, for: [peer], certificates: certificates, window: SyncSession.window(at: sender.clock.now),
            identities: identities)
        try await mailbox.put(packet, to: receiverID, in: pairs)
    }

    @Test("Identities nothing in a packet needs are not kept, are not passed on, and stop no message")
    func strangersAreNotKept() async throws {
        let t = try await RoomOfThree.make()
        let before = t.carol.replica.knownParticipants
        let made = try strangers(2_000)

        try await writePacket(
            from: t.sam, to: t.carol, through: t.mailbox, identities: made.identities, certificates: made.certificates)
        let round = try await t.carol.sync(through: t.mailbox, media: t.mailbox)

        #expect(t.carol.replica.knownParticipants == before, "an identity nothing needed was kept")
        #expect(round.credentialsRejected == 0, "a packet of junk counted as something this phone must wait for")

        try await t.carol.send("still here", to: t.room)
        try await t.settle()
        #expect(t.alice.messages(in: t.room).contains { $0.body == "still here" })
        #expect(!t.alice.replica.knownParticipants.contains(made.identities[0].participantID))
    }

    @Test("A phone already holding twenty thousand strangers sends in packets that carry none of them")
    func aPoisonedPhoneStillSends() async throws {
        let t = try await RoomOfThree.make()
        for _ in 0..<20_000 { t.carol.replica.introduce(Identity.generate().publicKeys) }

        try await t.carol.send("through the crowd", to: t.room)
        let round = try await t.carol.sync(through: t.mailbox, media: t.mailbox)

        #expect(round.sendFailure == nil)
        #expect(round.entriesSent >= 1)
        let largest = await t.mailbox.largestPacketBytes
        #expect(largest < 64 * 1024, "a packet carried identities its entries did not need: \(largest) bytes")
        try await t.settle()
        #expect(t.alice.messages(in: t.room).contains { $0.body == "through the crowd" })
        #expect(t.alice.replica.knownParticipants.count < 20)
    }

    @Test("Working out who to address costs what this phone is in touch with, not who it has heard of")
    func pairsDoNotWalkStrangers() async throws {
        let t = try await RoomOfThree.make()
        for _ in 0..<20_000 { t.carol.replica.introduce(Identity.generate().publicKeys) }

        let cost = ContinuousClock().measure { _ = t.carol.pairs() }

        #expect(cost < .milliseconds(500), "pairs() took \(cost)")
        #expect(t.carol.pairs()?.hints.count == 2)
    }

    @Test("A packet naming more new authors than a packet can is cut off at that many")
    func theCountIsCapped() async throws {
        var replica = Replica()
        var entries: [Entry] = []
        var identities: [IdentityPublicKeys] = []
        var certificates: [DeviceCertificate] = []
        for _ in 0..<(SyncSession.mostIdentitiesInAPacket + 40) {
            var author = Author()
            identities.append(author.identity.publicKeys)
            certificates.append(author.certificate)
            entries.append(try author.post("hello", at: TestSession.now))
        }
        let delivery = SyncEngine.Delivery(
            entries: entries, certificates: certificates, revocations: [], grants: [], identities: identities)
        let collected = SyncSession.CollectedPackets(
            tags: [],
            packets: [
                .init(
                    id: PacketID(), delivery: delivery, storedAt: TestSession.now,
                    from: ParticipantID(rawValue: Data()))
            ])

        SyncSession.integrate(collected, into: &replica)

        #expect(replica.knownParticipants.count == SyncSession.mostIdentitiesInAPacket)
    }

    @Test("An author's identity and certificates ride every packet that carries their entries")
    func eachPacketStandsAlone() async throws {
        let t = try await RoomOfThree.make()
        var burst: [Entry] = []
        var bob = Author()
        for index in 0..<300 {
            burst.append(try bob.post(String(repeating: "lantern ", count: 1_000) + "\(index)", at: TestSession.now))
        }
        let pairs = try #require(t.alice.pairs())
        let session = SyncSession(mailbox: t.mailbox, pairs: pairs, clock: t.alice.clock)
        let peer = try #require(t.alice.peers().first { $0.them == t.carolID })

        let report = try await session.send(
            burst, to: [peer], certificates: [bob.certificate], identities: [bob.identity.publicKeys])

        #expect(report.packetsWritten >= 2, "precondition: more than one packet")
        let reader = SyncSession(mailbox: t.mailbox, pairs: try #require(t.carol.pairs()), clock: t.carol.clock)
        let collected = try await reader.collect(
            as: try #require(t.carol.peers().first { $0.them == t.aliceID }))
        #expect(collected.packets.count == report.packetsWritten)
        for packet in collected.packets {
            #expect(packet.delivery.identities.contains(bob.identity.publicKeys))
            #expect(packet.delivery.certificates.contains(bob.certificate))
        }
    }

    @Test("Everything in a first packet counts against the budget, and keys spill into packets of their own")
    func everythingCounts() async throws {
        let t = try await RoomOfThree.make()
        let pairs = try #require(t.alice.pairs())
        let session = SyncSession(mailbox: t.mailbox, pairs: pairs, clock: t.alice.clock)
        let peer = try #require(t.alice.peers().first { $0.them == t.carolID })
        let links = try (0..<UInt64(EpochChain.mostLinksInAGrant)).map {
            try EpochChain.advance(from: .random(), at: EpochNumber(rawValue: $0), room: t.room).link
        }
        var granting: [(to: Peer, grant: EpochGrant)] = []
        for index in 0..<6 {
            granting.append(
                (peer, try EpochGrant.issue(
                    .random(), at: EpochNumber(rawValue: UInt64(index)), in: t.room, link: nil, links: links,
                    to: peer.secret, devices: t.alice.deviceRecipients(of: t.carolID)
                ).signed(by: try #require(t.alice.enrolment?.device), from: t.aliceID, to: t.carolID)))
        }
        var author = Author()
        let burst = try (0..<60).map { _ in
            try author.post(String(repeating: "lantern ", count: 1_000), at: TestSession.now)
        }

        let report = try await session.send(
            burst, to: [peer], certificates: [author.certificate], granting: granting,
            identities: [author.identity.publicKeys])

        #expect(report.sendFailure == nil)
        #expect(report.written.flatMap(\.grants).count == granting.count, "a key was left behind")
        #expect(report.entriesSent == burst.count)
        let largest = await t.mailbox.largestPacketBytes
        #expect(largest <= SyncSession.packetByteBudget + 4_096, "a packet over the budget: \(largest)")
    }

    @Test("A key too big for any packet fails on its own, and everything else goes")
    func aHugeKeyFailsAlone() async throws {
        let t = try await RoomOfThree.make()
        let pairs = try #require(t.alice.pairs())
        let session = SyncSession(mailbox: t.mailbox, pairs: pairs, clock: t.alice.clock)
        let peer = try #require(t.alice.peers().first { $0.them == t.carolID })
        let huge = EpochGrant(
            room: t.room, epoch: .initial, link: nil, links: [],
            wrapped: Data(count: SyncSession.packetByteBudget * 2))
        var author = Author()
        let entry = try author.post("hello", at: TestSession.now)

        let report = try await session.send(
            [entry], to: [peer], certificates: [author.certificate], granting: [(peer, huge)],
            identities: [author.identity.publicKeys])

        #expect(report.entriesSent == 1)
        #expect(report.written.flatMap(\.grants).isEmpty, "a key that did not go was reported as sent")
    }

    @Test("A record the mailbox will not take fails that packet, not the round, even when it is every packet")
    func aTooLargeRecordFailsThatItem() async throws {
        let t = try await RoomOfThree.make()
        try await t.carol.send("for both", to: t.room)
        let tooLarge = MailboxError.recordTooLarge(bytes: 2_000_000, ceiling: MailboxRules.recordByteCeiling)
        await t.mailbox.failWrite(number: 1, with: tooLarge)
        await t.mailbox.failWrite(number: 2, with: tooLarge)

        let round = try await t.carol.sync(through: t.mailbox, media: t.mailbox)

        #expect(round.sendFailure != nil, "the failure was not reported")
        #expect(round.packetsWritten == 0, "precondition: every packet failed")
        try await t.settle()
        #expect(t.alice.messages(in: t.room).contains { $0.body == "for both" })
        #expect(t.sam.messages(in: t.room).contains { $0.body == "for both" })
    }

    @Test("A key that rode a packet that failed is offered again")
    func aKeyThatFailedIsNotMarkedSent() async throws {
        let t = try await RoomOfThree.make()
        try await t.alice.advanceEpoch(of: t.room)
        await t.mailbox.failNextWrite(with: .recordTooLarge(bytes: 2_000_000, ceiling: MailboxRules.recordByteCeiling))

        let round = try await t.alice.sync(through: t.mailbox, media: t.mailbox)

        let missed = Set([t.carolID, t.samID]).subtracting(round.written.compactMap(\.to))
        try #require(missed.count == 1, "precondition: one person's packet failed and the other's landed")
        #expect(try t.alice.grantsOwed().contains { missed.contains($0.to.them) }, "the key that did not go was marked sent")
    }

    @Test("A member with more devices than anybody has stops being added to, and their old ones still count")
    func aRegistryIsBounded() throws {
        let identity = Identity.generate()
        var registry = DeviceRegistry(identity: identity.publicKeys)
        let founding = try DeviceCertificate.recovered(for: DeviceKeys.generate(), by: identity, at: TestSession.now)
        try registry.admit(founding)
        for _ in 0..<(DeviceRegistry.mostDevices + 10) {
            try registry.admit(
                try DeviceCertificate.recovered(for: DeviceKeys.generate(), by: identity, at: TestSession.now))
        }
        #expect(registry.certificates.count <= DeviceRegistry.mostDevices)
        #expect(registry.standing(of: founding.device) != nil)
    }
}
