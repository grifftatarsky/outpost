import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("A device the stolen phone removed itself stops when the member removes the stolen phone", .tags(.crypto))
struct ADeviceTheStolenPhoneRemovedItselfTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let identity = Identity.generate()
    private let phone = DeviceKeys.generate()
    private let stolen = DeviceKeys.generate()
    private let hidden = DeviceKeys.generate()
    private let chain = EpochChain.create(room: RoomID()).chain

    private func friend() throws -> Replica {
        var replica = Replica()
        replica.introduce(identity.publicKeys)
        try replica.admit(DeviceCertificate.recovered(for: phone, by: identity, at: start), storedAt: start)
        try replica.admit(
            DeviceCertificate.issue(for: stolen, by: identity, at: start + 10, approvedBy: phone), storedAt: start + 10)
        try replica.admit(
            DeviceCertificate.issue(for: hidden, by: identity, at: start + 20, approvedBy: stolen), storedAt: start + 20)
        return replica
    }

    @Test("A device the thief approved, then removed with a cutoff of the thief's choosing, writes nothing once the stolen phone is removed")
    func theThiefsOwnRemovalIsNotAPass() throws {
        var replica = try friend()
        try replica.revoke(
            DeviceRevocation.issue(
                for: hidden.id, by: identity, at: start + 30, from: stolen,
                cutoff: 1 << 40, head: EntryHash(rawValue: Data(repeating: 7, count: 32)), remaining: [stolen.id]),
            storedAt: start + 30)
        try replica.revoke(
            DeviceRevocation.issue(
                for: stolen.id, by: identity, at: start + 100, from: phone,
                cutoff: 0, head: nil, remaining: [phone.id]),
            storedAt: start + 100)
        try #require(
            replica.registry(for: identity.id)?.standing(of: hidden.id)?.revokedAt != nil,
            "precondition: the member's list shows the hidden device as removed already, so nothing offers to remove it")

        let post = try Entry.append(
            to: nil, author: identity.id, device: hidden, clock: VectorClock(), wallTime: start + 5000, room: nil,
            payload: try Payload.post("written as the member after they removed the stolen phone"), at: .initial,
            sealedWith: chain)

        #expect(
            throws: (any Error).self,
            "a device the thief approved and removed itself, with a cutoff it chose, still writes as the member") {
                try replica.integrate(post)
            }
    }
}
