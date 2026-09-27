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
            try DeviceCertificate.recovered(for: phone, by: identity, at: start),
            try DeviceCertificate.issue(for: tablet, by: identity, at: start + 60, approvedBy: phone),
        ])
        #expect(registry.standing(of: tablet.id)?.approvedBy == phone.id)
        #expect(registry.isAuthorized(tablet.id, at: start + 120))
    }

    @Test("A device can be approved by a device that was itself approved")
    func approvalsChain() throws {
        let (phone, tablet, laptop) = (DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate())
        let registry = try registry([
            try DeviceCertificate.recovered(for: phone, by: identity, at: start),
            try DeviceCertificate.issue(for: tablet, by: identity, at: start + 60, approvedBy: phone),
            try DeviceCertificate.issue(for: laptop, by: identity, at: start + 120, approvedBy: tablet),
        ])
        #expect(registry.isAuthorized(laptop.id, at: start + 180))
    }

    @Test("Certificates can arrive in any order")
    func orderDoesNotMatter() throws {
        let (phone, tablet, laptop) = (DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate())
        let certificates = [
            try DeviceCertificate.recovered(for: phone, by: identity, at: start),
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

        try registry.admit(try DeviceCertificate.recovered(for: phone, by: identity, at: start))
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
            try DeviceCertificate.recovered(for: phone, by: identity, at: start), forged,
        ])
        #expect(!registry.isAuthorized(tablet.id, at: start + 120), "an approval the phone never signed counted")
    }

    @Test("A device removed before an approval can't approve anything")
    func aRemovedDeviceCannotApprove() throws {
        let (phone, tablet, stranger) = (DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate())
        let registry = try registry(
            [
                try DeviceCertificate.recovered(for: phone, by: identity, at: start),
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
                try DeviceCertificate.recovered(for: phone, by: identity, at: start),
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
                try DeviceCertificate.recovered(for: phone, by: identity, at: start),
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

    @Test("A certificate made with the identity alone never counts, so holding the identity lets nobody in")
    func theIdentityAloneLetsNobodyIn() throws {
        let (phone, intruder) = (DeviceKeys.generate(), DeviceKeys.generate())
        let registry = try registry([
            try DeviceCertificate.recovered(for: phone, by: identity, at: start),
            try DeviceCertificate.issue(for: intruder, by: identity.withoutRecovery, at: start + 60),
        ])
        #expect(!registry.isAuthorized(intruder.id, at: start + 120))
        #expect(registry.standing(of: intruder.id) == nil)
        #expect(!registry.isPending(intruder.id), "a certificate that can never count was waiting as if it might")
        #expect(registry.activeDevices == [phone.id])
    }

    @Test("The recovery key makes a device count and removes every other one, including ones a thief added")
    func theRecoveryKeyResetsTheDevices() throws {
        let (phone, stolen, thiefs, restored, later) = (
            DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate(),
            DeviceKeys.generate()
        )
        var registry = DeviceRegistry(identity: identity.publicKeys)
        try registry.admit(DeviceCertificate.recovered(for: phone, by: identity, at: start), storedAt: start)
        try registry.admit(
            DeviceCertificate.issue(for: stolen, by: identity, at: start + 10, approvedBy: phone), storedAt: start + 10)
        try registry.admit(
            DeviceCertificate.issue(for: thiefs, by: identity, at: start + 20, approvedBy: stolen), storedAt: start + 20)
        try registry.revoke(
            DeviceRevocation.issue(for: phone.id, by: identity, at: start + 30, from: stolen), storedAt: start + 30)
        #expect(registry.activeDevices == [stolen.id, thiefs.id], "the setup did not model a thief who took over")

        try registry.admit(
            DeviceCertificate.recovered(for: restored, by: identity, at: start + 100), storedAt: start + 100)
        #expect(registry.activeDevices == [restored.id])
        #expect(registry.standing(of: stolen.id)?.removedByRecovery == true)
        #expect(registry.standing(of: thiefs.id)?.removedByRecovery == true)
        #expect(registry.standing(of: restored.id)?.recovered == true)

        try registry.admit(
            DeviceCertificate.issue(for: DeviceKeys.generate(), by: identity, at: start + 90, approvedBy: stolen),
            storedAt: start + 200)
        try registry.revoke(
            DeviceRevocation.issue(for: restored.id, by: identity, at: start + 90, from: thiefs), storedAt: start + 200)
        #expect(registry.activeDevices == [restored.id], "a removed device acted after the reset")

        try registry.admit(
            DeviceCertificate.issue(for: later, by: identity, at: start + 300, approvedBy: restored), storedAt: start + 300)
        #expect(registry.activeDevices == [restored.id, later.id])
    }

    @Test("Hearing of a reset first and the thief's devices afterwards still removes them")
    func aResetHeardFirstStillCounts() throws {
        let (phone, stolen, restored) = (DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate())
        var registry = DeviceRegistry(identity: identity.publicKeys)
        try registry.admit(
            DeviceCertificate.recovered(for: restored, by: identity, at: start + 100), storedAt: start + 100)
        try registry.admit(
            DeviceCertificate.issue(for: stolen, by: identity, at: start + 10, approvedBy: phone), storedAt: start + 10)
        try registry.admit(DeviceCertificate.recovered(for: phone, by: identity, at: start), storedAt: start)
        #expect(registry.activeDevices == [restored.id])
    }
}

@Suite("Approving a device, across two of the member's devices", .serialized)
@MainActor
struct ApprovingADeviceTests {
    @Test("Restoring with the recovery key on a new device removes the member's other devices, and they erase themselves")
    func aRestoreRemovesTheOthers() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let phone = TestSession.make(keychain: keychain)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        await phone.load()
        try await phone.createIdentity(displayName: "Griff")
        let key = try #require(phone.recoveryKeyText())
        await phone.noteRecoveryKeySaved()

        let restored = TestSession.make(keychain: InMemoryKeychainStore(), clock: TestClock(now: TestSession.now + 60))
        restored.syncDevices(through: InMemoryEntrySync(relay: relay))
        await restored.load()
        try await restored.restore(fromRecoveryKey: key)
        let restoredDevice = try #require(restored.enrolment?.device.id)
        #expect(restored.state == .ready || restored.state == .needsProfile)

        await phone.settleDeviceSync { phone.state == .removed }
        #expect(phone.state == .removed, "the old device kept going after a restore")
        #expect(phone.enrolment == nil)
        #expect(try await IdentityStore(keychain: keychain).loadIdentity() == nil, "the removed device kept the identity")
        let member = try #require(restored.enrolment?.identity.id)
        let registry = try #require(restored.replica.registry(for: member))
        #expect(registry.activeDevices == [restoredDevice])
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
        tablet.checkAccount(with: StubAccountRegistry(hasMember: true))
        await tablet.settleRegistration()
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
        tablet.checkAccount(with: StubAccountRegistry(hasMember: true))
        await tablet.settleRegistration()
        let waiting = try #require(tablet.pendingDevice?.id)
        await phone.settleDeviceSync { !phone.deviceRequests.isEmpty }

        let member = try #require(phone.enrolment?.identity.id)
        #expect(!phone.deviceRecipients(of: member).contains { $0.device == waiting })
    }
}
