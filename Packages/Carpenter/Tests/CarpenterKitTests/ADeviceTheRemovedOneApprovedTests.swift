@testable import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("The app's removal names every device it keeps", .serialized)
@MainActor
struct TheAppNamesTheDevicesItKeepsTests {
    @Test("Removing one device names this device and every other one that still counts")
    func theRemovalNamesWhatRemains() async throws {
        let clock = TestClock(now: TestSession.now)
        let session = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        await session.load()
        try await session.createIdentity(displayName: "Griff")
        let enrolment = try #require(session.enrolment)

        var spares: [DeviceID] = []
        for _ in 0..<2 {
            clock.advance(by: 3600)
            let keys = DeviceKeys.generate()
            try session.replica.admit(
                DeviceCertificate.issue(for: keys, by: enrolment.identity, at: clock.now, approvedBy: enrolment.device))
            spares.append(keys.id)
        }

        try await session.revoke(spares[0])

        let removal = session.replica.registry(for: enrolment.identity.id)?.knownRevocations
            .first { $0.device == spares[0] }
        #expect(removal.map { Set($0.remaining) } == [enrolment.device.id, spares[1]])
    }
}

@Suite("A device the removed one approved, and the member never saw, goes with it")
struct ADeviceTheRemovedOneApprovedTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let identity = Identity.generate()
    private let phone = DeviceKeys.generate()
    private let stolen = DeviceKeys.generate()
    private let hidden = DeviceKeys.generate()
    private let hiddenToo = DeviceKeys.generate()

    private func registry() throws -> DeviceRegistry {
        var registry = DeviceRegistry(identity: identity.publicKeys)
        try registry.admit(DeviceCertificate.recovered(for: phone, by: identity, at: start), storedAt: start)
        try registry.admit(
            DeviceCertificate.issue(for: stolen, by: identity, at: start + 10, approvedBy: phone), storedAt: start + 10)
        return registry
    }

    private func approval(of device: DeviceKeys, by approver: DeviceKeys, at instant: Date) throws -> DeviceCertificate {
        try DeviceCertificate.issue(for: device, by: identity, at: instant, approvedBy: approver)
    }

    private func removal(of device: DeviceKeys, remaining: Set<DeviceID>) throws -> DeviceRevocation {
        try DeviceRevocation.issue(
            for: device.id, by: identity, at: start + 100, from: phone,
            cutoff: 0, head: nil, remaining: remaining)
    }

    @Test("A friend that saw the hidden device before the removal and the member after it agree on who counts")
    func theFriendAndTheMemberAgree() throws {
        var friend = try registry()
        try friend.admit(try approval(of: hidden, by: stolen, at: start + 20), storedAt: start + 20)
        try friend.admit(try approval(of: hiddenToo, by: hidden, at: start + 30), storedAt: start + 30)
        try friend.revoke(try removal(of: stolen, remaining: [phone.id]), storedAt: start + 100)

        var member = try registry()
        try member.revoke(try removal(of: stolen, remaining: [phone.id]), storedAt: start + 100)
        try member.admit(try approval(of: hidden, by: stolen, at: start + 20), storedAt: start + 200)

        #expect(friend.activeDevices == [phone.id], "a device the stolen phone approved outlived its removal")
        #expect(friend.activeDevices == member.activeDevices)
        #expect(!friend.counts(hidden.id, storedAt: start + 150), "the hidden device could still announce an address")
        #expect(!friend.counts(hiddenToo.id, storedAt: start + 150), "a device the hidden one approved still counted")
        #expect(!friend.isAuthorized(hidden.id, at: start + 50, seq: 1), "the hidden device's words still counted")
    }

    @Test("A device the removed one approved and the remover names stays")
    func aNamedDeviceStays() throws {
        var friend = try registry()
        try friend.admit(try approval(of: hidden, by: stolen, at: start + 20), storedAt: start + 20)
        try friend.revoke(try removal(of: stolen, remaining: [phone.id, hidden.id]), storedAt: start + 100)

        #expect(friend.activeDevices == [phone.id, hidden.id])
        #expect(friend.counts(hidden.id, storedAt: start + 150))
    }

    @Test("A device somebody else approved is not touched by the list")
    func anotherLineageIsUntouched() throws {
        var friend = try registry()
        try friend.admit(try approval(of: hidden, by: phone, at: start + 20), storedAt: start + 20)
        try friend.revoke(try removal(of: stolen, remaining: [phone.id]), storedAt: start + 100)

        #expect(friend.activeDevices == [phone.id, hidden.id])
    }

    @Test("A device the removed one had already removed is cut back to what the member's devices had seen of it")
    func anAlreadyRemovedDeviceIsCutBack() throws {
        for seenByThePhone in [0, 5] as [UInt64] {
            var friend = try registry()
            try friend.admit(try approval(of: hidden, by: stolen, at: start + 20), storedAt: start + 20)
            if seenByThePhone > 0 {
                var clock = VectorClock()
                clock.observe(FeedKey(author: identity.id, device: hidden.id), seq: seenByThePhone)
                friend.noteWhatWasSeen(by: phone.id, in: clock)
            }
            try friend.revoke(
                DeviceRevocation.issue(
                    for: hidden.id, by: identity, at: start + 40, from: stolen,
                    cutoff: 7, head: EntryHash(rawValue: Data(repeating: 7, count: 32)), remaining: [stolen.id]),
                storedAt: start + 40)
            try friend.revoke(try removal(of: stolen, remaining: [phone.id]), storedAt: start + 100)

            #expect(
                friend.line(of: hidden.id) == seenByThePhone,
                "the cutoff the removed device chose for a device it approved outlived its own removal")
        }
    }

    @Test("A device the member's own phone had already removed keeps the line that removal drew")
    func aDeviceTheMemberRemovedKeepsItsLine() throws {
        var friend = try registry()
        try friend.admit(try approval(of: hidden, by: stolen, at: start + 20), storedAt: start + 20)
        try friend.revoke(
            DeviceRevocation.issue(
                for: hidden.id, by: identity, at: start + 40, from: phone,
                cutoff: 7, head: EntryHash(rawValue: Data(repeating: 7, count: 32)), remaining: [phone.id]),
            storedAt: start + 40)
        try friend.revoke(try removal(of: stolen, remaining: [phone.id]), storedAt: start + 100)

        #expect(friend.line(of: hidden.id) == 7)
    }

    @Test("The list is signed: changing it breaks the removal")
    func theListIsSigned() throws {
        var revocation = try removal(of: stolen, remaining: [phone.id, hidden.id])
        try revocation.verify(against: identity.publicKeys)
        revocation.remaining = [phone.id]
        #expect(throws: (any Error).self) { try revocation.verify(against: identity.publicKeys) }
    }

    @Test("A list longer than a member may have devices is refused")
    func aLongListIsRefused() throws {
        let many = Set((0...DeviceRegistry.mostDevices).map { _ in DeviceKeys.generate().id })
        let revocation = try removal(of: stolen, remaining: many)
        #expect(throws: (any Error).self) { try revocation.verify(against: identity.publicKeys) }
    }

    @Test("A removal signs its remover, its cutoff, the entry at it and the devices that remain, in that order")
    func theLayout() throws {
        let head = EntryHash(rawValue: Data(repeating: 7, count: 32))
        let ids = [phone.id, hidden.id].sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
        let revocation = try DeviceRevocation.issue(
            for: stolen.id, by: identity, at: start + 1000, from: phone,
            cutoff: 4, head: head, remaining: Set(ids))
        let expected = CanonicalBytes.payload(
            domain: Domain.deviceRevocation,
            fields: [
                identity.id.rawValue, stolen.id.rawValue, CanonicalBytes.timestamp(start + 1000),
                Data("revoked-by".utf8), phone.id.rawValue, Data("cutoff".utf8), CanonicalBytes.sequence(4),
                Data("head".utf8), head.rawValue,
                Data("remaining".utf8), CanonicalBytes.sequence(2),
            ] + ids.map(\.rawValue))
        #expect(revocation.signingPayload == expected)
    }

    @Test("A removal survives coding with its list")
    func theListSurvivesCoding() throws {
        let removal = try removal(of: stolen, remaining: [phone.id])
        #expect(try JSONDecoder().decode(DeviceRevocation.self, from: JSONEncoder().encode(removal)) == removal)
    }
}
