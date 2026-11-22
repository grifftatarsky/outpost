import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("What vouches for a removed device's entry can arrive in a later packet", .tags(.crypto, .sync))
struct WhatVouchesForAnEntryCanArriveInALaterPacketTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let identity = Identity.generate()
    private let phone = DeviceKeys.generate()
    private let stolen = DeviceKeys.generate()
    private let tablet = DeviceKeys.generate()
    private let chain = EpochChain.create(room: RoomID()).chain

    private func friend() throws -> Replica {
        var replica = Replica()
        replica.introduce(identity.publicKeys)
        try replica.admit(DeviceCertificate.recovered(for: phone, by: identity, at: start), storedAt: start)
        for (index, device) in [stolen, tablet].enumerated() {
            let at = start + 10 + Double(index)
            try replica.admit(DeviceCertificate.issue(for: device, by: identity, at: at, approvedBy: phone), storedAt: at)
        }
        return replica
    }

    private func feed(of device: DeviceKeys, _ count: Int, seeing: VectorClock = VectorClock()) throws -> [Entry] {
        var head: Entry?
        var written: [Entry] = []
        for _ in 0..<count {
            var clock = seeing
            if let head { clock.observe(head.feedKey, seq: head.seq) }
            let entry = try Entry.append(
                to: head, author: identity.id, device: device, clock: clock,
                wallTime: start + 100 + Double(head?.seq ?? 0), room: nil,
                payload: try Payload.post("\(head?.seq ?? 0)"), at: .initial, sealedWith: chain)
            head = entry
            written.append(entry)
        }
        return written
    }

    private func packet(_ entries: [Entry], storedAt: Date) -> SyncSession.CollectedPackets.Opened {
        .init(
            id: PacketID(),
            delivery: SyncEngine.Delivery(entries: entries, certificates: [], revocations: [], grants: [], identities: []),
            storedAt: storedAt, from: identity.id)
    }

    private func held(_ replica: Replica) -> [UInt64] {
        replica.allEntries.filter { $0.device == stolen.id }.map(\.seq).sorted()
    }

    @Test("Two friends given the same packets in a different order keep the same history of a removed device")
    func theOrderOfPacketsDoesNotMatter() throws {
        let words = try feed(of: stolen, 5)
        var seeing = VectorClock()
        seeing.observe(words[4].feedKey, seq: words[4].seq)
        let vouch = try feed(of: tablet, 1, seeing: seeing)
        let removal = try DeviceRevocation.issue(
            for: stolen.id, by: identity, at: start + 1000, from: phone,
            cutoff: words[2].seq, head: words[2].hash, remaining: [phone.id])

        var first = try friend()
        var second = try friend()
        for entry in words.prefix(3) {
            try first.integrate(entry)
            try second.integrate(entry)
        }
        try first.revoke(removal, storedAt: start + 1000)
        try second.revoke(removal, storedAt: start + 1000)

        let late = packet(Array(words.suffix(2)), storedAt: start + 1100)
        let witness = packet(vouch, storedAt: start + 1200)

        let (lateFirst, settledFirst) = SyncSession.integrate(
            SyncSession.CollectedPackets(tags: [], packets: [late]), into: &first)
        SyncSession.integrate(SyncSession.CollectedPackets(tags: [], packets: [witness]), into: &first)
        let stillOffered = [late].filter { !settledFirst.contains($0.id) }
        SyncSession.integrate(SyncSession.CollectedPackets(tags: [], packets: stillOffered), into: &first)

        SyncSession.integrate(SyncSession.CollectedPackets(tags: [], packets: [witness]), into: &second)
        SyncSession.integrate(SyncSession.CollectedPackets(tags: [], packets: [late]), into: &second)

        #expect(held(second) == [1, 2, 3, 4, 5], "precondition: the tablet's clock vouches for what it had seen")
        #expect(lateFirst.entriesRefusedForever == 0, "a refusal another of the member's devices could still lift was final")
        #expect(
            held(first) == held(second),
            """
            the friend who got the stolen phone's entries before the tablet's was told the refusal was final \
            (\(lateFirst.entriesRefusedForever) refused for good, packet settled: \(settledFirst.contains(late.id))), \
            so the app acknowledges the packet and records the numbers as unverifiable, and repair never asks again
            """)
    }

    @Test("Once the packet is gone, history repair still asks for what the member's tablet vouched for")
    func repairAsksForWhatWasVouchedFor() throws {
        let words = try feed(of: stolen, 5)
        var seeing = VectorClock()
        seeing.observe(words[4].feedKey, seq: words[4].seq)
        let vouch = try feed(of: tablet, 1, seeing: seeing)
        var replica = try friend()
        for entry in words.prefix(3) { try replica.integrate(entry) }
        try replica.revoke(
            DeviceRevocation.issue(
                for: stolen.id, by: identity, at: start + 1000, from: phone,
                cutoff: 3, head: words[2].hash, remaining: [phone.id]),
            storedAt: start + 1000)

        let (late, _) = SyncSession.integrate(
            SyncSession.CollectedPackets(tags: [], packets: [packet(Array(words.suffix(2)), storedAt: start + 1100)]),
            into: &replica)
        #expect(replica.gaps().allSatisfy { $0.feed != words[0].feedKey }, "precondition: nothing vouches for 4 and 5 yet")
        SyncSession.integrate(
            SyncSession.CollectedPackets(tags: [], packets: [packet(vouch, storedAt: start + 1200)]), into: &replica)

        let givenUpOn = Set(late.refusals.filter(\.isFinal).compactMap(\.seq))
        let asked = (replica.gaps().first { $0.feed == words[0].feedKey }?.spans ?? [])
            .flatMap { Array($0.lower...$0.upper) }.filter { !givenUpOn.contains($0) }
        #expect(asked == [4, 5], "what the tablet had seen of the removed device was never asked for again")
    }

    @Test("A refusal past the cutoff is final once no other device of the member could vouch for it")
    func nobodyLeftToVouch() throws {
        let words = try feed(of: stolen, 4)
        var replica = Replica()
        replica.introduce(identity.publicKeys)
        try replica.admit(DeviceCertificate.recovered(for: phone, by: identity, at: start), storedAt: start)
        try replica.admit(
            DeviceCertificate.issue(for: stolen, by: identity, at: start + 10, approvedBy: phone), storedAt: start + 10)
        for entry in words.prefix(3) { try replica.integrate(entry) }
        try replica.revoke(
            DeviceRevocation.issue(
                for: stolen.id, by: identity, at: start + 1000, from: phone,
                cutoff: 3, head: words[2].hash, remaining: [phone.id]),
            storedAt: start + 1000)
        #expect(throws: (any Error).self) { try replica.integrate(words[3]) }
        #expect(!replica.refusesForever(words[3]), "the member's phone could still vouch, and the refusal was final")

        try replica.revoke(
            DeviceRevocation.issue(
                for: phone.id, by: identity, at: start + 2000, from: phone,
                cutoff: 0, head: nil, remaining: [phone.id]), storedAt: start + 2000)
        #expect(replica.refusesForever(words[3]), "nobody is left to vouch, and the refusal is still not final")
    }
}
