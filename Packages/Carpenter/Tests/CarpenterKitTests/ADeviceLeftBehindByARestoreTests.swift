import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("A device a recovery key left behind stops at what each contact held when it heard")
struct ADeviceLeftBehindByARestoreTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let identity = Identity.generate()
    private let phone = DeviceKeys.generate()
    private let stolen = DeviceKeys.generate()
    private let restored = DeviceKeys.generate()
    private let chain = EpochChain.create(room: RoomID()).chain

    private var restoredAt: Date { start + 5000 }

    private func oldCertificates() throws -> [DeviceCertificate] {
        [
            try DeviceCertificate.recovered(for: phone, by: identity, at: start),
            try DeviceCertificate.issue(for: stolen, by: identity, at: start + 10, approvedBy: phone),
        ]
    }

    private func newRoot() throws -> DeviceCertificate {
        try DeviceCertificate.recovered(for: restored, by: identity, at: restoredAt)
    }

    private func contact() throws -> Replica {
        var replica = Replica()
        replica.introduce(identity.publicKeys)
        for certificate in try oldCertificates() { try replica.admit(certificate, storedAt: certificate.issuedAt) }
        return replica
    }

    private func feed(_ count: Int, from head: Entry? = nil, dated: Date? = nil) throws -> [Entry] {
        var previous = head
        var written: [Entry] = []
        for _ in 0..<count {
            let entry = try Entry.append(
                to: previous, author: identity.id, device: stolen, clock: VectorClock(),
                wallTime: dated ?? start + 100 + Double(previous?.seq ?? 0), room: nil,
                payload: try Payload.post("\(previous?.seq ?? 0)"), at: .initial, sealedWith: chain)
            previous = entry
            written.append(entry)
        }
        return written
    }

    private func hear(_ root: DeviceCertificate, in replica: inout Replica, sparing member: ParticipantID? = nil) throws {
        try replica.admit(root, storedAt: restoredAt + 1)
        replica.fixSupersededLines(sparing: member)
    }

    @Test("After the restore, a backdated entry at the next number from the old device is refused")
    func aBackdatedEntryIsRefused() throws {
        var replica = try contact()
        let words = try feed(3)
        for entry in words { try replica.integrate(entry) }

        try hear(try newRoot(), in: &replica)

        let backdated = try feed(1, from: words[2], dated: start + 200)
        #expect(throws: (any Error).self, "the old device signed past the restore with a date before it") {
            try replica.integrate(backdated[0])
        }
        #expect(replica.refusesForever(backdated[0]))
        #expect(replica.allEntries.map(\.hash) == words.map(\.hash), "what the contact held was taken away")
    }

    @Test("A second entry at the number the line names is refused")
    func aForkAtTheLineIsRefused() throws {
        var replica = try contact()
        let words = try feed(3)
        for entry in words { try replica.integrate(entry) }
        try hear(try newRoot(), in: &replica)

        let forged = try feed(1, from: words[1], dated: start + 150)
        #expect(throws: (any Error).self) { try replica.integrate(forged[0]) }
    }

    @Test("A contact that held nothing of the old device when it heard takes nothing of it afterwards")
    func nothingHeldMeansNothingTaken() throws {
        var replica = try contact()
        try hear(try newRoot(), in: &replica)

        let backdated = try feed(1, dated: start + 200)
        #expect(throws: (any Error).self) { try replica.integrate(backdated[0]) }
    }

    @Test("The order the certificates arrive in does not change the line")
    func theOrderOfCertificatesDoesNotMatter() throws {
        var first = Replica()
        first.introduce(identity.publicKeys)
        try first.admit(try newRoot(), storedAt: restoredAt + 1)
        for certificate in try oldCertificates() { try first.admit(certificate, storedAt: certificate.issuedAt) }
        first.fixSupersededLines(sparing: nil)

        var second = try contact()
        try hear(try newRoot(), in: &second)

        #expect(first.supersededLines == second.supersededLines)
        #expect(first.supersededLines[FeedKey(author: identity.id, device: stolen.id)]?.seq == 0)
    }

    @Test("The member's own devices are spared, so a restored device can still be given its history")
    func theMembersOwnDevicesAreSpared() throws {
        var replica = Replica()
        replica.introduce(identity.publicKeys)
        try replica.admit(try newRoot(), storedAt: restoredAt + 1)
        for certificate in try oldCertificates() { try replica.admit(certificate, storedAt: certificate.issuedAt) }
        replica.fixSupersededLines(sparing: identity.id)

        let history = try feed(3)
        for entry in history { try replica.integrate(entry) }
        #expect(replica.allEntries.count == 3, "the restored device refused its member's own history")
    }

    @Test("A line kept on disk is put back before the log is read, so a relaunch draws it the same")
    func aRestoredLineHolds() throws {
        var before = try contact()
        let words = try feed(3)
        for entry in words { try before.integrate(entry) }
        try hear(try newRoot(), in: &before)
        let kept = before.supersededLines

        var after = try contact()
        try after.admit(try newRoot(), storedAt: restoredAt + 1)
        after.restore(supersededLines: kept)
        let backdated = try feed(1, from: words[2], dated: start + 200)
        _ = after.integrate(words + backdated)
        after.fixSupersededLines(sparing: nil)

        #expect(after.allEntries.map(\.hash) == words.map(\.hash))
        #expect(after.supersededLines == kept)
    }

    @Test("A packet carrying the new root and a backdated entry from the old device takes the root and refuses the entry")
    func aPacketCarryingBoth() throws {
        var replica = try contact()
        let words = try feed(2)
        for entry in words { try replica.integrate(entry) }
        let backdated = try feed(1, from: words[1], dated: start + 200)
        let delivery = SyncEngine.Delivery(
            entries: backdated, certificates: [try newRoot()], revocations: [], grants: [], identities: [])
        let collected = SyncSession.CollectedPackets(
            tags: [],
            packets: [.init(id: PacketID(), delivery: delivery, storedAt: restoredAt + 1, from: identity.id)])

        let (report, _) = SyncSession.integrate(collected, into: &replica, sparing: ParticipantID(rawValue: WideID.of([1])))

        #expect(report.entriesRefusedForever == 1)
        #expect(replica.allEntries.map(\.hash) == words.map(\.hash))
    }

    @Test("A line is fixed once: nothing offered later moves it")
    func aLineIsFixedOnce() throws {
        var replica = try contact()
        let words = try feed(2)
        try replica.integrate(words[0])
        try hear(try newRoot(), in: &replica)
        let feed = FeedKey(author: identity.id, device: stolen.id)
        replica.restore(supersededLines: [feed: DeviceRegistry.Line(seq: 99, head: nil)])
        replica.fixSupersededLines(sparing: nil)

        #expect(replica.supersededLines[feed]?.seq == 1)
        #expect(throws: (any Error).self) { try replica.integrate(words[1]) }
    }
}
