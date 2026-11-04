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
            for: stolen.id, by: identity, at: start + 1000, from: phone, cutoff: words[2].seq, head: words[2].hash)

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

        SyncSession.integrate(SyncSession.CollectedPackets(tags: [], packets: [witness]), into: &second)
        SyncSession.integrate(SyncSession.CollectedPackets(tags: [], packets: [late]), into: &second)

        #expect(held(second) == [1, 2, 3, 4, 5], "precondition: the tablet's clock vouches for what it had seen")
        #expect(
            held(first) == held(second),
            """
            the friend who got the stolen phone's entries before the tablet's was told the refusal was final \
            (\(lateFirst.entriesRefusedForever) refused for good, packet settled: \(settledFirst.contains(late.id))), \
            so the app acknowledges the packet and records the numbers as unverifiable, and repair never asks again
            """)
    }
}
