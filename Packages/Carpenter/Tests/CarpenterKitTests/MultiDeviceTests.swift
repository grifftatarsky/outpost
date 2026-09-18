import Foundation
import Testing

@testable import CarpenterKit

@Suite("One member, two devices")
struct MultiDeviceTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let chain = EpochChain.create(room: RoomID()).chain

    private func seal(_ text: String) throws -> SealedPayload {
        try Payload.post(text).sealed(at: .initial, using: chain)
    }

    @Test("Both of a member's devices write their own feed, and a third member verifies both")
    func bothFeedsVerify() throws {
        let identity = Identity.generate()
        let phone = DeviceKeys.generate()
        let mac = DeviceKeys.generate()

        let phoneCertificate = try DeviceCertificate.issue(
            for: phone.publicKey, by: identity, at: start)
        let macCertificate = try DeviceCertificate.issue(
            for: mac.publicKey, by: identity, at: start.addingTimeInterval(60))

        var hastur = Replica()
        hastur.introduce(identity.publicKeys)
        try hastur.admit(phoneCertificate)
        try hastur.admit(macCertificate)

        let room = RoomID()
        let fromPhone = try Entry.append(
            to: nil, author: identity.id, device: phone, clock: VectorClock(),
            wallTime: start.addingTimeInterval(120), room: room,
            payload: try seal("posted from the phone"))

        var seen = VectorClock()
        seen.observe(fromPhone.feedKey, seq: fromPhone.seq)
        let fromMac = try Entry.append(
            to: nil, author: identity.id, device: mac, clock: seen,
            wallTime: start.addingTimeInterval(180), room: room,
            payload: try seal("and from the Mac"))

        #expect(try hastur.integrate(fromPhone) == .accepted)
        #expect(try hastur.integrate(fromMac) == .accepted)
        #expect(!hastur.hasDiverged)

        let rendered = Fold.render(hastur.entries(in: room), using: chain)
        #expect(rendered.count == 2)
        #expect(Set(rendered.map(\.author)) == [identity.id])
        #expect(Set(rendered.map(\.device)) == [phone.id, mac.id])
        #expect(rendered.map(\.id) == [fromPhone.hash, fromMac.hash])
    }

    @Test("Two devices posting while unaware of each other do not fork")
    func concurrentDevicesDoNotFork() throws {
        let identity = Identity.generate()
        let phone = DeviceKeys.generate()
        let mac = DeviceKeys.generate()

        var replica = Replica()
        replica.introduce(identity.publicKeys)
        try replica.admit(DeviceCertificate.issue(for: phone.publicKey, by: identity, at: start))
        try replica.admit(DeviceCertificate.issue(for: mac.publicKey, by: identity, at: start))

        for device in [phone, mac] {
            try replica.integrate(
                Entry.append(
                    to: nil, author: identity.id, device: device, clock: VectorClock(),
                    wallTime: start.addingTimeInterval(60), room: nil,
                    payload: try seal("written offline")))
        }

        #expect(!replica.hasDiverged)
        #expect(replica.entryCount == 2)
    }

    @Test("Revoking one device leaves the other member's history readable and the other device working")
    func revokingOneDevice() throws {
        let identity = Identity.generate()
        let kept = DeviceKeys.generate()
        let lost = DeviceKeys.generate()

        var replica = Replica()
        replica.introduce(identity.publicKeys)
        try replica.admit(DeviceCertificate.issue(for: kept.publicKey, by: identity, at: start))
        try replica.admit(DeviceCertificate.issue(for: lost.publicKey, by: identity, at: start))

        let room = RoomID()
        let beforeLoss = try Entry.append(
            to: nil, author: identity.id, device: lost, clock: VectorClock(),
            wallTime: start.addingTimeInterval(60), room: room,
            payload: try seal("said before the phone was lost"))
        try replica.integrate(beforeLoss)

        let revokedAt = start.addingTimeInterval(3_600)
        try replica.revoke(DeviceRevocation.issue(for: lost.id, by: identity, at: revokedAt))

        let afterLoss = try Entry.append(
            to: beforeLoss, author: identity.id, device: lost, clock: beforeLoss.clock,
            wallTime: revokedAt.addingTimeInterval(60), room: room,
            payload: try seal("posted by a thief"))
        #expect(throws: LogError.unauthorizedDevice) { try replica.integrate(afterLoss) }

        let carryOn = try Entry.append(
            to: nil, author: identity.id, device: kept, clock: VectorClock(),
            wallTime: revokedAt.addingTimeInterval(120), room: room,
            payload: try seal("replacement phone"))
        #expect(try replica.integrate(carryOn) == .accepted)

        let rendered = Fold.render(replica.entries(in: room), using: chain)
        #expect(rendered.map(\.id) == [beforeLoss.hash, carryOn.hash])
    }
}
