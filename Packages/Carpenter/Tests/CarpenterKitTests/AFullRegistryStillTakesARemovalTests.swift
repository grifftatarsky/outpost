@testable import CarpenterKit
import Foundation
import Testing

@Suite("A removed device cannot fill a member's registry so that what the member does next stops counting")
struct AFullRegistryStillTakesARemovalTests {
    private let t0 = Date(timeIntervalSince1970: 1_786_635_000)

    private struct Household {
        var registry: DeviceRegistry
        let identity: Identity
        let phone: DeviceKeys
        let thief: DeviceKeys
    }

    private func household() throws -> Household {
        let identity = Identity.generate()
        let phone = DeviceKeys.generate()
        let thief = DeviceKeys.generate()
        var registry = DeviceRegistry(identity: identity.publicKeys)
        try registry.admit(DeviceCertificate.recovered(for: phone, by: identity, at: t0), storedAt: t0)
        try registry.admit(
            DeviceCertificate.issue(for: thief, by: identity, at: t0 + 10, approvedBy: phone), storedAt: t0 + 10)
        #expect(registry.counts(thief.id, storedAt: t0 + 11), "precondition: the phone approved the second device")
        return Household(registry: registry, identity: identity, phone: phone, thief: thief)
    }

    private func junk(from house: Household) throws -> (certificates: [DeviceCertificate], revocations: [DeviceRevocation]) {
        let certificates = try (0..<DeviceRegistry.mostDevices).map { _ in
            try DeviceCertificate.issue(
                for: DeviceKeys.generate(), by: house.identity, at: t0 + 20, approvedBy: house.thief)
        }
        let revocations = try (0..<DeviceRegistry.mostDevices).map { second in
            try DeviceRevocation.issue(
                for: certificates[0].device, by: house.identity, at: t0 + 30 + TimeInterval(second), from: house.thief)
        }
        return (certificates, revocations)
    }

    private func flood(_ house: inout Household) throws {
        let made = try junk(from: house)
        for certificate in made.certificates { try house.registry.admit(certificate, storedAt: t0 + 20) }
        for revocation in made.revocations { try house.registry.revoke(revocation, storedAt: revocation.revokedAt) }
    }

    @Test("The member's removal of a stolen phone still counts after that phone fills the registry")
    func theRemovalStillCounts() throws {
        var house = try household()
        try flood(&house)

        try house.registry.revoke(
            DeviceRevocation.issue(for: house.thief.id, by: house.identity, at: t0 + 500, from: house.phone),
            storedAt: t0 + 500)

        let stillCounts = house.registry.counts(house.thief.id, storedAt: t0 + 600)
        #expect(!stillCounts, "the member removed the stolen phone and it still counts")
    }

    @Test("A phone the member approves after the registry was filled still counts")
    func aNewPhoneStillCounts() throws {
        var house = try household()
        try flood(&house)
        let newPhone = DeviceKeys.generate()

        try house.registry.admit(
            DeviceCertificate.issue(for: newPhone, by: house.identity, at: t0 + 500, approvedBy: house.phone),
            storedAt: t0 + 500)

        let counts = house.registry.counts(newPhone.id, storedAt: t0 + 600)
        #expect(counts, "the member's new phone was never let in")
    }

    @Test("Restoring with the recovery key still cuts off every older device after the registry was filled")
    func theRecoveryKeyStillCuts() throws {
        var house = try household()
        try flood(&house)
        let restored = DeviceKeys.generate()

        try house.registry.admit(
            DeviceCertificate.recovered(for: restored, by: house.identity, at: t0 + 500), storedAt: t0 + 500)

        let restoredCounts = house.registry.counts(restored.id, storedAt: t0 + 600)
        let thiefCounts = house.registry.counts(house.thief.id, storedAt: t0 + 600)
        #expect(restoredCounts, "the restored phone was never let in")
        #expect(!thiefCounts, "the recovery key did not cut off the stolen phone")
    }

    @Test("A contact still refuses the stolen phone's next entry after one packet of its making and the member's removal")
    func aContactStillRefusesTheStolenPhone() throws {
        let house = try household()
        let made = try junk(from: house)
        var replica = Replica()
        replica.introduce(house.identity.publicKeys)
        try replica.admit(DeviceCertificate.recovered(for: house.phone, by: house.identity, at: t0), storedAt: t0)
        try replica.admit(
            DeviceCertificate.issue(for: house.thief, by: house.identity, at: t0 + 10, approvedBy: house.phone),
            storedAt: t0 + 10)

        func packet(certificates: [DeviceCertificate], revocations: [DeviceRevocation], at stored: Date)
            -> SyncSession.CollectedPackets
        {
            SyncSession.CollectedPackets(
                tags: [],
                packets: [
                    .init(
                        id: PacketID(),
                        delivery: SyncEngine.Delivery(
                            entries: [], certificates: certificates, revocations: revocations, grants: [],
                            identities: []),
                        storedAt: stored, from: house.identity.id)
                ])
        }
        SyncSession.integrate(packet(certificates: made.certificates, revocations: made.revocations, at: t0 + 40), into: &replica)
        let removal = try DeviceRevocation.issue(for: house.thief.id, by: house.identity, at: t0 + 500, from: house.phone)
        SyncSession.integrate(packet(certificates: [], revocations: [removal], at: t0 + 500), into: &replica)

        let afterwards = try Entry.append(
            to: nil, author: house.identity.id, device: house.thief, clock: VectorClock(), wallTime: t0 + 700,
            room: nil, payload: Payload.post("still me"), at: .initial,
            sealedWith: EpochChain.create(room: RoomID()).chain, roomLink: nil)

        #expect(throws: LogError.unauthorizedDevice, "a contact took an entry from a phone its member had removed") {
            try replica.integrate(afterwards)
        }
    }

    private func claimingThePhone(from house: Household) throws -> DeviceCertificate {
        let made = DeviceKeys.generate()
        var certificate = DeviceCertificate(
            participant: house.identity.id, device: made.id, devicePublicKey: made.publicKey, issuedAt: t0 + 20,
            signature: Data(), approvedBy: house.phone.id, approval: Data())
        certificate.signature = try house.identity.sign(certificate.signingPayload)
        certificate.approval = try house.thief.sign(certificate.signingPayload)
        return certificate
    }

    @Test("Certificates that falsely name the member's phone, or an approver nobody has seen, leave the phone's approvals alone")
    func madeUpApprovalsTakeNoPlaceOfThePhones() throws {
        var house = try household()
        for _ in 0..<DeviceRegistry.mostDevices {
            try house.registry.admit(claimingThePhone(from: house), storedAt: t0 + 20)
            try house.registry.admit(
                DeviceCertificate.issue(
                    for: DeviceKeys.generate(), by: house.identity, at: t0 + 20, approvedBy: DeviceKeys.generate()),
                storedAt: t0 + 20)
        }
        let newPhones = (0..<(DeviceRegistry.mostApprovalsByOneDevice - 1)).map { _ in DeviceKeys.generate() }
        for newPhone in newPhones {
            try house.registry.admit(
                DeviceCertificate.issue(for: newPhone, by: house.identity, at: t0 + 500, approvedBy: house.phone),
                storedAt: t0 + 500)
        }

        let counting = newPhones.filter { house.registry.counts($0.id, storedAt: t0 + 600) }.count
        #expect(counting == newPhones.count, "only \(counting) of the phones the member approved count")
    }

    @Test("Every list the registry keeps stays bounded however much one identity holder sends")
    func everythingKeptIsBounded() throws {
        var house = try household()
        try flood(&house)
        for _ in 0..<DeviceRegistry.mostDevices {
            try house.registry.admit(claimingThePhone(from: house), storedAt: t0 + 20)
        }

        let kept = house.registry.deviceIDs.count
        #expect(kept <= 2 + DeviceRegistry.mostApprovalsByOneDevice, "the registry counts \(kept) devices")
        #expect(house.registry.knownRevocations.count <= DeviceRegistry.mostRemovalsByOneDevice)
    }

    @Test("A batch that lists a device before the device that approved it is admitted approvers first")
    func aBatchIsAdmittedApproversFirst() throws {
        let identity = Identity.generate()
        let root = DeviceKeys.generate()
        let middle = DeviceKeys.generate()
        let last = DeviceKeys.generate()
        let first = try DeviceCertificate.recovered(for: root, by: identity, at: t0)
        let second = try DeviceCertificate.issue(for: middle, by: identity, at: t0 + 1, approvedBy: root)
        let third = try DeviceCertificate.issue(for: last, by: identity, at: t0 + 2, approvedBy: middle)

        #expect([third, second, first].approversFirst.map(\.device) == [root.id, middle.id, last.id])
    }
}
