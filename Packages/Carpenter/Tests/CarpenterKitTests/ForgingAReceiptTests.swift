import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("A receipt counts only when the device it names signed it while it counted")
struct ForgingAReceiptTests {
    private let t0 = Date(timeIntervalSince1970: 1_786_635_000)
    private let sender = Identity.generate()
    private let member = Identity.generate()
    private let phone = DeviceKeys.generate()
    private let stolen = DeviceKeys.generate()
    private let packet = PacketID()
    private let tag = RecipientTag(rawValue: Data([1, 2, 3]))

    private func registry() throws -> DeviceRegistry {
        var registry = DeviceRegistry(identity: member.publicKeys)
        try registry.admit(DeviceCertificate.recovered(for: phone, by: member, at: t0), storedAt: t0)
        try registry.admit(
            DeviceCertificate.issue(for: stolen, by: member, at: t0 + 10, approvedBy: phone), storedAt: t0 + 10)
        try registry.revoke(
            DeviceRevocation.issue(for: stolen.id, by: member, at: t0 + 20, from: phone), storedAt: t0 + 20)
        return registry
    }

    private func open(_ sealed: SealedReceipt, for packet: PacketID? = nil) throws -> PacketReceipt? {
        let senderSide = try PairwiseSecret.derive(mine: sender, theirs: member.publicKeys)
        return PacketReceipt.open(
            sealed, for: packet ?? self.packet, from: member.id, with: senderSide, by: try registry())
    }

    @Test("A receipt the member's phone signed is taken, for that packet only")
    func genuineIsTaken() throws {
        let memberSide = try PairwiseSecret.derive(mine: member, theirs: sender.publicKeys)
        let genuine = try PacketReceipt.seal(packet, under: tag, as: member.id, by: phone, to: memberSide)
        #expect(try open(genuine) != nil)
        #expect(try open(genuine, for: PacketID()) == nil, "a receipt for one packet was taken for another")
    }

    @Test("A removed device can't sign for its member, in its own name or in the phone's")
    func removedDeviceCannotSignFor() throws {
        let memberSide = try PairwiseSecret.derive(mine: member, theirs: sender.publicKeys)
        let own = try PacketReceipt.seal(packet, under: tag, as: member.id, by: stolen, to: memberSide)
        #expect(try open(own) == nil, "a removed device signed for a packet meant for its member")

        let claimed = PacketReceipt(
            participant: member.id, device: phone.id,
            signature: try stolen.sign(PacketReceipt.signed(packet, participant: member.id, device: phone.id)))
        let forged = SealedReceipt(
            tag: tag,
            sealed: try memberSide.wrap(
                try JSONEncoder().encode(claimed), context: PacketReceipt.context(packet, tag: tag)))
        #expect(try open(forged) == nil, "a receipt naming the phone, signed by the removed device, was taken")
    }
}
