import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("A record between a member's devices counts only with its writer's signature")
struct SigningSiblingRecordsTests {
    private let member = Identity.generate()
    private let phone = DeviceKeys.generate()
    private let tablet = DeviceKeys.generate()

    private func sealed(by signer: DeviceKeys?, as kind: SiblingRecord.Kind = .state) throws -> SealedSiblingFeed {
        try SealedSiblingFeed.seal(
            SiblingFeed(entries: [], certificates: [], member: member.id), for: member, on: phone.id, as: kind,
            signedBy: signer)
    }

    @Test("A record signed by the device that wrote it checks out, for that device and that kind only")
    func signedChecksOut() throws {
        let record = try sealed(by: phone)
        #expect(record.isSigned(by: phone.publicKey, member: member.id, device: phone.id, as: .state))
        #expect(
            !record.isSigned(by: phone.publicKey, member: member.id, device: phone.id, as: .request),
            "a signature on one kind of record was taken for another")
        #expect(
            !record.isSigned(by: phone.publicKey, member: Identity.generate().id, device: phone.id, as: .state),
            "a signature for one member was taken for another")
    }

    @Test("A record nobody signed, or signed by another device, or altered, does not check out")
    func forgedDoesNotCheckOut() throws {
        let unsigned = try sealed(by: nil)
        #expect(!unsigned.isSigned(by: phone.publicKey, member: member.id, device: phone.id, as: .state))

        let record = try sealed(by: phone)
        #expect(
            !record.isSigned(by: tablet.publicKey, member: member.id, device: phone.id, as: .state),
            "a record checked out against a key that did not sign it")

        var bytes = record.ciphertext
        bytes[bytes.index(before: bytes.endIndex)] ^= 0x01
        #expect(
            !SealedSiblingFeed(ciphertext: bytes).isSigned(
                by: phone.publicKey, member: member.id, device: phone.id, as: .state),
            "an altered record still checked out")

        #expect(throws: CryptoError.deviceMismatch) {
            try SealedSiblingFeed.seal(
                SiblingFeed(entries: [], certificates: [], member: member.id), for: member, on: phone.id,
                signedBy: tablet)
        }
    }
}
