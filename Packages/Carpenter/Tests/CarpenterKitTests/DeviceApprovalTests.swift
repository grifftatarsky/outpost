import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp
@testable import CarpenterKit

@Suite("Which devices count as the member's")
struct DeviceApprovalTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let identity = Identity.generate()

    private func registry(_ certificates: [DeviceCertificate], _ revocations: [DeviceRevocation] = [])
        throws -> DeviceRegistry
    {
        var registry = DeviceRegistry(identity: identity.publicKeys)
        for certificate in certificates { try registry.admit(certificate) }
        for revocation in revocations { try registry.revoke(revocation) }
        return registry
    }

    @Test("The first device counts, and a device it approves counts")
    func anApprovedDeviceCounts() throws {
        let (phone, tablet) = (DeviceKeys.generate(), DeviceKeys.generate())
        let registry = try registry([
            try DeviceCertificate.issue(for: phone, by: identity, at: start),
            try DeviceCertificate.issue(for: tablet, by: identity, at: start + 60, approvedBy: phone),
        ])
        #expect(registry.standing(of: tablet.id)?.approvedBy == phone.id)
        #expect(registry.isAuthorized(tablet.id, at: start + 120))
    }

    @Test("A device can be approved by a device that was itself approved")
    func approvalsChain() throws {
        let (phone, tablet, laptop) = (DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate())
        let registry = try registry([
            try DeviceCertificate.issue(for: phone, by: identity, at: start),
            try DeviceCertificate.issue(for: tablet, by: identity, at: start + 60, approvedBy: phone),
            try DeviceCertificate.issue(for: laptop, by: identity, at: start + 120, approvedBy: tablet),
        ])
        #expect(registry.isAuthorized(laptop.id, at: start + 180))
    }

    @Test("Certificates can arrive in any order")
    func orderDoesNotMatter() throws {
        let (phone, tablet, laptop) = (DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate())
        let certificates = [
            try DeviceCertificate.issue(for: phone, by: identity, at: start),
            try DeviceCertificate.issue(for: tablet, by: identity, at: start + 60, approvedBy: phone),
            try DeviceCertificate.issue(for: laptop, by: identity, at: start + 120, approvedBy: tablet),
        ]
        let forwards = try registry(certificates)
        let backwards = try registry(certificates.reversed())
        #expect(forwards.activeDevices == backwards.activeDevices)
        #expect(backwards.activeDevices.count == 3)
    }

    @Test("An approval from a device the registry has not seen does not count until that device is known")
    func anUnknownApproverDoesNotCountYet() throws {
        let (phone, tablet) = (DeviceKeys.generate(), DeviceKeys.generate())
        var registry = try registry([
            try DeviceCertificate.issue(for: tablet, by: identity, at: start + 60, approvedBy: phone)
        ])
        #expect(!registry.isAuthorized(tablet.id, at: start + 120))
        #expect(registry.isPending(tablet.id))

        try registry.admit(try DeviceCertificate.issue(for: phone, by: identity, at: start))
        #expect(registry.isAuthorized(tablet.id, at: start + 120))
    }

    @Test("An approval signed by some other key does not count")
    func aForgedApprovalDoesNotCount() throws {
        let (phone, tablet) = (DeviceKeys.generate(), DeviceKeys.generate())
        var forged = try DeviceCertificate.issue(
            for: tablet, by: identity, at: start + 60, approvedBy: DeviceKeys.generate())
        forged.approvedBy = phone.id
        forged.signature = try identity.sign(forged.signingPayload)

        let registry = try registry([
            try DeviceCertificate.issue(for: phone, by: identity, at: start), forged,
        ])
        #expect(!registry.isAuthorized(tablet.id, at: start + 120), "an approval the phone never signed counted")
    }

    @Test("A device removed before an approval can't approve anything")
    func aRemovedDeviceCannotApprove() throws {
        let (phone, tablet, stranger) = (DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate())
        let registry = try registry(
            [
                try DeviceCertificate.issue(for: phone, by: identity, at: start),
                try DeviceCertificate.issue(for: tablet, by: identity, at: start + 60, approvedBy: phone),
                try DeviceCertificate.issue(for: stranger, by: identity, at: start + 300, approvedBy: tablet),
            ],
            [try DeviceRevocation.issue(for: tablet.id, by: identity, at: start + 200, from: phone)])
        #expect(!registry.isAuthorized(stranger.id, at: start + 400), "a removed device let another one in")
    }

    @Test("A device approved before its approver was removed still counts")
    func earlierApprovalsStand() throws {
        let (phone, tablet, laptop) = (DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate())
        let registry = try registry(
            [
                try DeviceCertificate.issue(for: phone, by: identity, at: start),
                try DeviceCertificate.issue(for: tablet, by: identity, at: start + 60, approvedBy: phone),
                try DeviceCertificate.issue(for: laptop, by: identity, at: start + 120, approvedBy: tablet),
            ],
            [try DeviceRevocation.issue(for: tablet.id, by: identity, at: start + 200, from: phone)])
        #expect(registry.isAuthorized(laptop.id, at: start + 400), "removing the tablet threw out the laptop it approved")
        #expect(!registry.isAuthorized(tablet.id, at: start + 400))
    }

    @Test("A removal says which device made it, and a removal by a removed device does not count")
    func removalsNameTheirMaker() throws {
        let (phone, tablet, laptop) = (DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate())
        let registry = try registry(
            [
                try DeviceCertificate.issue(for: phone, by: identity, at: start),
                try DeviceCertificate.issue(for: tablet, by: identity, at: start + 60, approvedBy: phone),
                try DeviceCertificate.issue(for: laptop, by: identity, at: start + 120, approvedBy: phone),
            ],
            [
                try DeviceRevocation.issue(for: tablet.id, by: identity, at: start + 200, from: phone),
                try DeviceRevocation.issue(for: laptop.id, by: identity, at: start + 300, from: tablet),
            ])
        #expect(registry.standing(of: tablet.id)?.revokedBy == phone.id)
        #expect(registry.isAuthorized(laptop.id, at: start + 400), "a removed device removed another")
    }

    @Test("A certificate made with the identity alone is a root, and says so")
    func aRootSaysSo() throws {
        let (phone, restored) = (DeviceKeys.generate(), DeviceKeys.generate())
        let registry = try registry([
            try DeviceCertificate.issue(for: phone, by: identity, at: start),
            try DeviceCertificate.issue(for: restored, by: identity, at: start + 60),
        ])
        #expect(registry.standing(of: restored.id)?.isRoot == true)
        #expect(registry.isAuthorized(restored.id, at: start + 120))
    }
}

@Suite("Approving a device, across two of the member's devices", .serialized)
@MainActor
struct ApprovingADeviceTests {
    @Test("A device restored with the recovery key is flagged on the member's other devices")
    func aRecoveryRootIsFlagged() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let phone = TestSession.make(keychain: keychain)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        await phone.load()
        try await phone.createIdentity(displayName: "Griff")
        let key = try #require(phone.recoveryKeyText())

        let restored = TestSession.make(keychain: InMemoryKeychainStore())
        restored.syncDevices(through: InMemoryEntrySync(relay: relay))
        await restored.load()
        try await restored.restore(fromRecoveryKey: key)
        let restoredDevice = try #require(restored.enrolment?.device.id)

        await phone.settleDeviceSync { phone.devices.contains { $0.id == restoredDevice } }
        let listed = try #require(phone.devices.first { $0.id == restoredDevice })
        #expect(listed.addedWithTheRecoveryKey, "a device that skipped approval looked like any other")
    }

    @Test("A device approved in the ordinary way is not flagged")
    func anApprovedDeviceIsNotFlagged() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let phone = TestSession.make(keychain: keychain)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        await phone.load()
        try await phone.createIdentity(displayName: "Griff")

        let tablet = TestSession.make(keychain: await keychain.sibling())
        tablet.syncDevices(through: InMemoryEntrySync(relay: relay))
        await tablet.load()
        try await phone.approveNewDevice(tablet)
        let tabletDevice = try #require(tablet.enrolment?.device.id)
        await phone.settleDeviceSync()

        #expect(phone.devices.first { $0.id == tabletDevice }?.addedWithTheRecoveryKey == false)
    }

    @Test("A recovery key typed on a device waiting for approval lets it in without an approval")
    func theRecoveryKeyEndsTheWait() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let phone = TestSession.make(keychain: keychain)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        await phone.load()
        try await phone.createIdentity(displayName: "Griff")
        let key = try #require(phone.recoveryKeyText())

        let tablet = TestSession.make(keychain: await keychain.sibling())
        tablet.syncDevices(through: InMemoryEntrySync(relay: relay))
        await tablet.load()
        try #require(tablet.state == .awaitingApproval)

        try await tablet.restore(fromRecoveryKey: key)
        #expect(tablet.enrolment != nil)
        #expect(tablet.enrolment?.identity.id == phone.enrolment?.identity.id)
    }

    @Test("A reinstalled device that was approved before does not have to be approved again")
    func aReinstallIsRecognised() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let phone = TestSession.make(keychain: keychain)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        await phone.load()
        try await phone.createIdentity(displayName: "Griff")

        let tabletKeychain = await keychain.sibling()
        let tablet = TestSession.make(keychain: tabletKeychain)
        tablet.syncDevices(through: InMemoryEntrySync(relay: relay))
        await tablet.load()
        try await phone.approveNewDevice(tablet)

        let reinstalled = TestSession.make(keychain: tabletKeychain)
        reinstalled.syncDevices(through: InMemoryEntrySync(relay: relay))
        await reinstalled.load()
        #expect(reinstalled.state != .awaitingApproval, "a reinstall with the device's own keys asked for approval again")
        #expect(reinstalled.enrolment?.device.id == tablet.enrolment?.device.id)
    }

    @Test("A friend's room keys are never sealed to a device waiting for approval")
    func peersSealNothingToAWaitingDevice() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let phone = TestSession.make(keychain: keychain)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        await phone.load()
        try await phone.createIdentity(displayName: "Griff")

        let tablet = TestSession.make(keychain: await keychain.sibling())
        tablet.syncDevices(through: InMemoryEntrySync(relay: relay))
        await tablet.load()
        let waiting = try #require(tablet.pendingDevice?.id)
        await phone.settleDeviceSync { !phone.deviceRequests.isEmpty }

        let member = try #require(phone.enrolment?.identity.id)
        #expect(!phone.deviceRecipients(of: member).contains { $0.device == waiting })
    }
}
