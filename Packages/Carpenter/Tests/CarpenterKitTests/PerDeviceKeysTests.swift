import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp
@testable import CarpenterKit

@Suite("Each device has its own key", .tags(.crypto))
struct PerDeviceKeysTests {
    private let issued = Date(timeIntervalSince1970: 1_786_635_000)

    @Test("A certificate without a device key signs exactly the bytes it always did")
    func anOldCertificateKeepsItsBytes() throws {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        let certificate = try DeviceCertificate.issue(for: device.publicKey, by: identity, at: issued)

        func field(_ bytes: Data) -> Data {
            withUnsafeBytes(of: UInt32(bytes.count).bigEndian) { Data($0) } + bytes
        }
        let milliseconds = UInt64(issued.timeIntervalSince1970 * 1_000)
        let written = field(Data("carpenter.device-certificate.v1".utf8))
            + field(identity.id.rawValue) + field(device.id.rawValue) + field(device.publicKey)
            + field(withUnsafeBytes(of: milliseconds.bigEndian) { Data($0) })

        #expect(
            certificate.signingPayload == written,
            "adding the device key changed what every existing certificate was signed over, so none of them verify")
        try certificate.verify(against: identity.publicKeys)
    }

    @Test("The sealing key and the approver are each named in what the identity signs, the sealing key last")
    func theNewFieldsAreTagged() throws {
        let identity = Identity.generate()
        let (device, approver) = (DeviceKeys.generate(), DeviceKeys.generate())
        let certificate = try DeviceCertificate.issue(for: device, by: identity, at: issued, approvedBy: approver)

        func field(_ bytes: Data) -> Data {
            withUnsafeBytes(of: UInt32(bytes.count).bigEndian) { Data($0) } + bytes
        }
        let milliseconds = UInt64(issued.timeIntervalSince1970 * 1_000)
        let written = field(Data("carpenter.device-certificate.v1".utf8))
            + field(identity.id.rawValue) + field(device.id.rawValue) + field(device.publicKey)
            + field(withUnsafeBytes(of: milliseconds.bigEndian) { Data($0) })
            + field(Data("approved-by".utf8)) + field(approver.id.rawValue)
            + field(Data("sealing-key".utf8)) + field(device.sealingPublicKey)

        #expect(certificate.signingPayload == written)
        #expect(certificate.isApproved(byKey: approver.publicKey))
        #expect(!certificate.isApproved(byKey: device.publicKey))
    }

    @Test("A certificate from before the sealing key, carrying an X25519 key, signs the bytes it always did")
    func aCertificateWithAnAgreementKeyKeepsItsBytes() throws {
        let identity = Identity.generate()
        let (device, approver) = (DeviceKeys.generate(), DeviceKeys.generate())
        let agreementKey = Data(repeating: 9, count: 32)
        var certificate = DeviceCertificate(
            participant: identity.id, device: device.id, devicePublicKey: device.publicKey, issuedAt: issued,
            signature: Data(), agreementKey: agreementKey, approvedBy: approver.id)

        func field(_ bytes: Data) -> Data {
            withUnsafeBytes(of: UInt32(bytes.count).bigEndian) { Data($0) } + bytes
        }
        let milliseconds = UInt64(issued.timeIntervalSince1970 * 1_000)
        let written = field(Data("carpenter.device-certificate.v1".utf8))
            + field(identity.id.rawValue) + field(device.id.rawValue) + field(device.publicKey)
            + field(withUnsafeBytes(of: milliseconds.bigEndian) { Data($0) })
            + field(Data("agreement-key".utf8)) + field(agreementKey)
            + field(Data("approved-by".utf8)) + field(approver.id.rawValue)

        #expect(
            certificate.signingPayload == written,
            "adding the sealing key changed what every certificate with an X25519 key was signed over")
        certificate.signature = try identity.sign(written)
        certificate.approval = try approver.sign(written)
        try certificate.verify(against: identity.publicKeys)
        #expect(certificate.isApproved(byKey: approver.publicKey))
    }

    @Test("A certificate carrying a sealing key verifies, and changing or spoiling the key breaks it")
    func theSealingKeyIsSigned() throws {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        let certificate = try DeviceCertificate.issue(for: device, by: identity, at: issued)
        try certificate.verify(against: identity.publicKeys)

        var swapped = certificate
        swapped.sealingKey = DeviceKeys.generate().sealingPublicKey
        #expect(throws: CryptoError.badSignature) { try swapped.verify(against: identity.publicKeys) }

        var cut = try DeviceCertificate.issue(
            for: device.publicKey, sealingKey: Data(device.sealingPublicKey.dropLast()), by: identity, at: issued)
        #expect(throws: CryptoError.malformedKey) { try cut.verify(against: identity.publicKeys) }
        cut.sealingKey = nil
        #expect(throws: CryptoError.badSignature) { try cut.verify(against: identity.publicKeys) }
    }

    @Test("A device's certificate is never replaced, so nobody holding the identity can give it another key")
    func aCertificateIsNeverReplaced() throws {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        let thief = DeviceKeys.generate()
        var registry = DeviceRegistry(identity: identity.publicKeys)
        let real = try DeviceCertificate.recovered(for: device, by: identity, at: issued)
        try registry.admit(real)
        #expect(registry.sealingKey(for: device.id) == device.sealingPublicKey)

        var forged = DeviceCertificate(
            participant: identity.id, device: device.id, devicePublicKey: device.publicKey, issuedAt: issued,
            signature: Data(), agreementKey: Data(repeating: 1, count: 32), sealingKey: thief.sealingPublicKey)
        forged.signature = try identity.sign(forged.signingPayload)
        try registry.admit(forged)

        #expect(
            registry.sealingKey(for: device.id) == device.sealingPublicKey,
            "a certificate signed by the identity alone gave the device a key the thief holds")
        #expect(registry.certificates == [real])
        #expect(registry.standing(of: device.id)?.addedAt == issued)

        let silent = DeviceKeys.generate()
        try registry.admit(try DeviceCertificate.recovered(for: silent.publicKey, by: identity, at: issued))
        try registry.admit(try DeviceCertificate.recovered(for: silent, by: identity, at: issued))
        #expect(registry.sealingKey(for: silent.id) == nil, "a device with no sealing key was given one afterwards")
    }

    @Test("A room key sealed to a member's devices opens on each of them and on nothing else")
    func aGrantOpensOnlyOnItsDevices() throws {
        let sender = Identity.generate()
        let member = Identity.generate()
        let (phone, tablet, removed) = (DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate())
        let pairwise = try PairwiseSecret.derive(mine: sender, theirs: member.publicKeys)
        let theirs = try PairwiseSecret.derive(mine: member, theirs: sender.publicKeys)
        let secret = EpochSecret.random()

        let grant = try EpochGrant.issue(
            secret, at: .initial, in: RoomID(), link: nil, to: pairwise,
            devices: [phone, tablet].map { DeviceRecipient(device: $0.id, sealingKey: $0.sealingPublicKey) })

        #expect(try grant.open(with: theirs, as: phone) == secret)
        #expect(try grant.open(with: theirs, as: tablet) == secret)
        #expect(throws: CryptoError.notSealedForThisDevice) { try grant.open(with: theirs, as: removed) }
        #expect(throws: CryptoError.notSealedForThisDevice) { try grant.open(with: theirs) }
        #expect(throws: (any Error).self, "the identity alone opened a key sealed to devices") {
            try grant.open(with: theirs, as: DeviceKeys.generate())
        }
    }

    @Test("A key sealed to a device needs the member's identity too")
    func aDeviceKeyAloneIsNotEnough() throws {
        let sender = Identity.generate()
        let member = Identity.generate()
        let phone = DeviceKeys.generate()
        let pairwise = try PairwiseSecret.derive(mine: sender, theirs: member.publicKeys)
        let grant = try EpochGrant.issue(
            EpochSecret.random(), at: .initial, in: RoomID(), link: nil, to: pairwise,
            devices: [DeviceRecipient(device: phone.id, sealingKey: phone.sealingPublicKey)])

        let stranger = try PairwiseSecret.derive(mine: Identity.generate(), theirs: sender.publicKeys)
        #expect(throws: (any Error).self) { try grant.open(with: stranger, as: phone) }
    }
}

@Suite("A removed device", .serialized, .tags(.crypto))
@MainActor
struct ARemovedDeviceTests {
    @Test("A removed device stays removed after a relaunch, and the recovery key brings it back")
    func theRecoveryKeyBringsItBack() async throws {
        let keychain = InMemoryKeychainStore()
        let session = TestSession.make(keychain: keychain)
        await session.load()
        try await session.createIdentity(displayName: "Griff")
        let key = try #require(session.recoveryKeyText())
        await session.eraseAfterRemoval()
        #expect(session.state == .removed)

        let relaunched = TestSession.make(keychain: keychain)
        await relaunched.load()
        #expect(relaunched.state == .removed, "a removed device enrolled itself again on the next launch")

        try await relaunched.restore(fromRecoveryKey: key)
        #expect(relaunched.enrolment != nil)
        #expect(relaunched.state != .removed)
    }

    @Test("A removed device keeps nothing of the member, so another member's recovery key finds nothing of theirs")
    func aRemovedDeviceKeepsNothing() async throws {
        let keychain = InMemoryKeychainStore()
        let session = TestSession.make(keychain: keychain)
        await session.load()
        try await session.createIdentity(displayName: "Griff")
        let mine = try #require(session.enrolment?.identity.id)
        await session.eraseAfterRemoval()
        #expect(try await IdentityStore(keychain: keychain).loadIdentity() == nil, "the identity survived removal")
        #expect(try await IdentityStore(keychain: keychain).loadDeviceKeys() == nil)
        #expect(try await IdentityStore(keychain: keychain).unsavedRecoveryKey() == nil)

        let other = TestSession.make()
        await other.load()
        try await other.createIdentity(displayName: "Somebody")
        let theirs = try #require(other.recoveryKeyText())

        let relaunched = TestSession.make(keychain: keychain, clock: TestClock(now: TestSession.now + 60))
        await relaunched.load()
        #expect(relaunched.state == .removed)
        try await relaunched.restore(fromRecoveryKey: theirs)
        #expect(relaunched.enrolment?.identity.id == other.enrolment?.identity.id)
        #expect(relaunched.enrolment?.identity.id != mine)
        #expect(relaunched.rooms.isEmpty && relaunched.replica.allEntries.isEmpty, "the first member's history came back")
    }

    @Test("What a removed device held is gone from it")
    func itsKeysAreGone() async throws {
        let keychain = InMemoryKeychainStore()
        let session = TestSession.make(keychain: keychain)
        await session.load()
        try await session.createIdentity(displayName: "Griff")
        let room = try await session.createRoom(named: "Kitchen")
        try await session.send("before", to: room)
        let epochKey = AppSession.epochKey(room, .initial)
        #expect(try await keychain.data(for: epochKey) != nil, "precondition: the room key is kept")

        await session.eraseAfterRemoval()

        #expect(try await keychain.data(for: epochKey) == nil, "a removed device kept a room key")
        #expect(try await keychain.data(for: IdentityStore.deviceKey) == nil, "a removed device kept its own key")
        #expect(session.rooms.isEmpty)
        #expect(session.entryCount == 0)
    }
}
