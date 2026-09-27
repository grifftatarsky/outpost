import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("A device counts only between the times iCloud stored its approval and its removal")
struct WhoCanRemoveADeviceTests {
    private let t0 = Date(timeIntervalSince1970: 1_786_635_000)

    private struct Household {
        var registry: DeviceRegistry
        let identity: Identity
        let phone: DeviceKeys
        let tablet: DeviceKeys
        let thief: DeviceKeys
    }

    private func household() throws -> Household {
        let identity = Identity.generate()
        let (phone, tablet, thief) = (DeviceKeys.generate(), DeviceKeys.generate(), DeviceKeys.generate())
        var registry = DeviceRegistry(identity: identity.publicKeys)
        try registry.admit(DeviceCertificate.recovered(for: phone, by: identity, at: t0), storedAt: t0)
        try registry.admit(
            DeviceCertificate.issue(for: tablet, by: identity, at: t0 + 10, approvedBy: phone), storedAt: t0 + 10)
        try registry.admit(
            DeviceCertificate.issue(for: thief, by: identity, at: t0 + 20, approvedBy: phone), storedAt: t0 + 20)
        try registry.revoke(
            DeviceRevocation.issue(for: thief.id, by: identity, at: t0 + 30, from: phone), storedAt: t0 + 30)
        #expect(!registry.counts(thief.id, storedAt: t0 + 31), "precondition: the thief's device was removed")
        #expect(registry.counts(phone.id, storedAt: t0 + 31) && registry.counts(tablet.id, storedAt: t0 + 31))
        return Household(registry: registry, identity: identity, phone: phone, tablet: tablet, thief: thief)
    }

    private func forgedRemoval(
        of target: DeviceID, namingAsRemover remover: DeviceID, signedBy signer: DeviceKeys, in house: Household,
        at when: Date
    ) throws -> DeviceRevocation {
        var forged = DeviceRevocation(
            participant: house.identity.id, device: target, revokedAt: when, signature: Data(), revokedBy: remover)
        forged.signature = try house.identity.sign(forged.signingPayload)
        forged.revokerSignature = try signer.sign(forged.signingPayload)
        return forged
    }

    @Test("A removed device holding the identity can't remove the phone by naming the tablet as the remover")
    func aForgedRemoverRemovesNobody() throws {
        var house = try household()
        let forged = try forgedRemoval(
            of: house.phone.id, namingAsRemover: house.tablet.id, signedBy: house.thief, in: house, at: t0 + 40)
        try house.registry.revoke(forged, storedAt: t0 + 40)
        #expect(house.registry.counts(house.phone.id, storedAt: t0 + 50), "a removal nobody real signed took the phone")
        #expect(house.registry.activeDevices.contains(house.phone.id))

        let real = try DeviceRevocation.issue(for: house.phone.id, by: house.identity, at: t0 + 60, from: house.tablet)
        try house.registry.revoke(real, storedAt: t0 + 60)
        #expect(!house.registry.counts(house.phone.id, storedAt: t0 + 61), "precondition: a real removal works")
    }

    @Test("A removed device can't remove the phone in its own name either, before or after it was removed")
    func aRemovedDeviceRemovesNobody() throws {
        var house = try household()
        let late = try DeviceRevocation.issue(for: house.phone.id, by: house.identity, at: t0 + 40, from: house.thief)
        try house.registry.revoke(late, storedAt: t0 + 40)
        let backdated = try DeviceRevocation.issue(
            for: house.tablet.id, by: house.identity, at: t0 + 25, from: house.thief)
        try house.registry.revoke(backdated, storedAt: t0 + 41)
        #expect(house.registry.counts(house.phone.id, storedAt: t0 + 50))
        #expect(house.registry.counts(house.tablet.id, storedAt: t0 + 50), "a removal dated into the past counted")
    }

    @Test("What a device wrote before iCloud stored its approval does not count")
    func nothingCountsBeforeTheApproval() throws {
        var house = try household()
        let late = DeviceKeys.generate()
        try house.registry.admit(
            DeviceCertificate.issue(for: late, by: house.identity, at: t0 + 100, approvedBy: house.phone),
            storedAt: t0 + 100)
        #expect(house.registry.counts(late.id, storedAt: t0 + 150))
        #expect(!house.registry.counts(late.id, storedAt: t0 + 99), "a record stored before the approval counted")
        #expect(!house.registry.counts(late.id, storedAt: t0), "a record stored long before the approval counted")
    }

    @Test("A removal signed by a device before iCloud stored that device's approval removes nobody")
    func aRemovalBeforeTheApprovalRemovesNobody() throws {
        var house = try household()
        let late = DeviceKeys.generate()
        let early = try DeviceRevocation.issue(for: house.tablet.id, by: house.identity, at: t0 + 50, from: late)
        try house.registry.admit(
            DeviceCertificate.issue(for: late, by: house.identity, at: t0 + 100, approvedBy: house.phone),
            storedAt: t0 + 100)
        try house.registry.revoke(early, storedAt: t0 + 50)
        #expect(house.registry.counts(house.tablet.id, storedAt: t0 + 150), "a removal stored before its signer counted")
    }
}
