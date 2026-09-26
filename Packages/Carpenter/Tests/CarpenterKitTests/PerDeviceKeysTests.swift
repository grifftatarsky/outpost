import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp
@testable import CarpenterKit

@Suite("Each device has its own key")
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

    @Test("The device key and the approver are each named in what the identity signs")
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
            + field(Data("agreement-key".utf8)) + field(device.agreementPublicKey)
            + field(Data("approved-by".utf8)) + field(approver.id.rawValue)

        #expect(certificate.signingPayload == written)
        #expect(certificate.isApproved(byKey: approver.publicKey))
        #expect(!certificate.isApproved(byKey: device.publicKey))
    }

    @Test("A certificate carrying a device key verifies, and changing the key breaks it")
    func theDeviceKeyIsSigned() throws {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        var certificate = try DeviceCertificate.issue(for: device, by: identity, at: issued)
        try certificate.verify(against: identity.publicKeys)

        certificate.agreementKey = DeviceKeys.generate().agreementPublicKey
        #expect(throws: CryptoError.self) { try certificate.verify(against: identity.publicKeys) }
    }

    @Test("An older certificate is replaced by one with a device key, and keeps the day it was added")
    func anOldCertificateIsUpgraded() throws {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        var registry = DeviceRegistry(identity: identity.publicKeys)
        try registry.admit(try DeviceCertificate.issue(for: device.publicKey, by: identity, at: issued))
        #expect(registry.agreementKey(for: device.id) == nil)

        try registry.admit(try DeviceCertificate.issue(for: device, by: identity, at: issued.addingTimeInterval(60)))
        #expect(registry.agreementKey(for: device.id) == nil, "a certificate with a later date was allowed to move the device's start")

        try registry.admit(try DeviceCertificate.issue(for: device, by: identity, at: issued))
        #expect(registry.agreementKey(for: device.id) == device.agreementPublicKey)
        #expect(registry.standing(of: device.id)?.addedAt == issued)
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
            devices: [phone, tablet].map { DeviceRecipient(device: $0.id, agreementKey: $0.agreementPublicKey) })

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
            devices: [DeviceRecipient(device: phone.id, agreementKey: phone.agreementPublicKey)])

        let stranger = try PairwiseSecret.derive(mine: Identity.generate(), theirs: sender.publicKeys)
        #expect(throws: (any Error).self) { try grant.open(with: stranger, as: phone) }
    }
}

@Suite("A removed device", .serialized)
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

    @Test("Another member's recovery key does not bring a removed device back")
    func anotherMembersKeyIsRefused() async throws {
        let keychain = InMemoryKeychainStore()
        let session = TestSession.make(keychain: keychain)
        await session.load()
        try await session.createIdentity(displayName: "Griff")
        await session.eraseAfterRemoval()

        let other = TestSession.make()
        await other.load()
        try await other.createIdentity(displayName: "Somebody")
        let theirs = try #require(other.recoveryKeyText())

        let relaunched = TestSession.make(keychain: keychain)
        await relaunched.load()
        await #expect(throws: (any Error).self) { try await relaunched.restore(fromRecoveryKey: theirs) }
        #expect(relaunched.state == .removed)
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
