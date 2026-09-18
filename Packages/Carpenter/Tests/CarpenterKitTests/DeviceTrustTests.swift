import Foundation
import Testing

@testable import CarpenterKit

@Suite("Device certificates")
struct DeviceCertificateTests {
    private let issuedAt = Date(timeIntervalSince1970: 1_786_635_000)

    @Test("An identity certifies its own device, and anyone holding the public keys can check it")
    func issueAndVerify() throws {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()

        let certificate = try DeviceCertificate.issue(
            for: device.publicKey, by: identity, at: issuedAt)

        #expect(certificate.participant == identity.id)
        #expect(certificate.device == device.id)
        try certificate.verify(against: identity.publicKeys)
    }

    @Test("A certificate does not verify against a different member's keys")
    func wrongIssuer() throws {
        let identity = Identity.generate()
        let impostor = Identity.generate()
        let device = DeviceKeys.generate()

        let certificate = try DeviceCertificate.issue(
            for: device.publicKey, by: identity, at: issuedAt)

        #expect(throws: CryptoError.participantMismatch) {
            try certificate.verify(against: impostor.publicKeys)
        }
    }

    @Test("Every signed field is covered — changing any one of them breaks the signature")
    func tamperDetection() throws {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        let other = DeviceKeys.generate()
        let certificate = try DeviceCertificate.issue(
            for: device.publicKey, by: identity, at: issuedAt)

        var swappedKey = certificate
        swappedKey.devicePublicKey = other.publicKey
        #expect(throws: CryptoError.self) { try swappedKey.verify(against: identity.publicKeys) }

        var swappedTime = certificate
        swappedTime.issuedAt = issuedAt.addingTimeInterval(1)
        #expect(throws: CryptoError.badSignature) { try swappedTime.verify(against: identity.publicKeys) }

        var swappedDevice = certificate
        swappedDevice.device = other.id
        #expect(throws: CryptoError.self) { try swappedDevice.verify(against: identity.publicKeys) }
    }

    @Test("The device ID must match the key it certifies")
    func deviceIDMustMatchKey() throws {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        let other = DeviceKeys.generate()

        var forged = try DeviceCertificate.issue(for: device.publicKey, by: identity, at: issuedAt)
        forged.device = other.id
        forged.signature = try identity.sign(forged.signingPayload)

        #expect(throws: CryptoError.deviceMismatch) {
            try forged.verify(against: identity.publicKeys)
        }
    }

    @Test("A revocation signature is not a valid certificate signature, and the reverse")
    func domainSeparation() throws {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        let certificate = try DeviceCertificate.issue(
            for: device.publicKey, by: identity, at: issuedAt)
        let revocation = try DeviceRevocation.issue(for: device.id, by: identity, at: issuedAt)

        var crossed = certificate
        crossed.signature = revocation.signature
        #expect(throws: CryptoError.badSignature) { try crossed.verify(against: identity.publicKeys) }

        var crossedBack = revocation
        crossedBack.signature = certificate.signature
        #expect(throws: CryptoError.badSignature) {
            try crossedBack.verify(against: identity.publicKeys)
        }
    }

    @Test("A certificate survives encoding, because it is published in-band")
    func codableRoundTrip() throws {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        let certificate = try DeviceCertificate.issue(
            for: device.publicKey, by: identity, at: issuedAt)

        let data = try JSONEncoder().encode(certificate)
        let restored = try JSONDecoder().decode(DeviceCertificate.self, from: data)

        #expect(restored == certificate)
        try restored.verify(against: identity.publicKeys)
    }
}

@Suite("Device registry")
struct DeviceRegistryTests {
    private let issuedAt = Date(timeIntervalSince1970: 1_786_635_000)

    private struct Enrolled {
        let identity: Identity
        let device: DeviceKeys
        var registry: DeviceRegistry
    }

    private func enrol() throws -> Enrolled {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        var registry = DeviceRegistry(identity: identity.publicKeys)
        try registry.admit(DeviceCertificate.issue(for: device.publicKey, by: identity, at: issuedAt))
        return Enrolled(identity: identity, device: device, registry: registry)
    }

    @Test("An admitted device may sign for its member")
    func admit() throws {
        let enrolled = try enrol()

        #expect(enrolled.registry.isAuthorized(enrolled.device.id, at: issuedAt))
        #expect(enrolled.registry.signingKey(for: enrolled.device.id) == enrolled.device.publicKey)
    }

    @Test("A device is not authorised before its certificate was issued")
    func notAuthorizedBeforeIssue() throws {
        let enrolled = try enrol()

        #expect(!enrolled.registry.isAuthorized(enrolled.device.id, at: issuedAt.addingTimeInterval(-1)))
    }

    @Test("An unknown device is never authorised")
    func unknownDevice() throws {
        let enrolled = try enrol()

        #expect(!enrolled.registry.isAuthorized(DeviceKeys.generate().id, at: issuedAt))
    }

    @Test("A certificate signed by anyone else is refused")
    func refusesForeignCertificate() throws {
        var enrolled = try enrol()
        let impostor = Identity.generate()
        let device = DeviceKeys.generate()

        #expect(throws: CryptoError.participantMismatch) {
            try enrolled.registry.admit(
                DeviceCertificate.issue(for: device.publicKey, by: impostor, at: issuedAt))
        }
    }

    @Test("Revocation stops a device from signing anything after the revocation instant")
    func revocation() throws {
        var enrolled = try enrol()
        let revokedAt = issuedAt.addingTimeInterval(3_600)

        try enrolled.registry.revoke(
            DeviceRevocation.issue(for: enrolled.device.id, by: enrolled.identity, at: revokedAt))

        #expect(!enrolled.registry.isAuthorized(enrolled.device.id, at: revokedAt))
        #expect(!enrolled.registry.isAuthorized(enrolled.device.id, at: revokedAt.addingTimeInterval(1)))
    }

    @Test("Entries signed before revocation stay valid")
    func revocationIsForwardOnly() throws {
        var enrolled = try enrol()
        let revokedAt = issuedAt.addingTimeInterval(3_600)

        try enrolled.registry.revoke(
            DeviceRevocation.issue(for: enrolled.device.id, by: enrolled.identity, at: revokedAt))

        #expect(enrolled.registry.isAuthorized(enrolled.device.id, at: issuedAt))
        #expect(enrolled.registry.isAuthorized(enrolled.device.id, at: revokedAt.addingTimeInterval(-1)))
    }

    @Test("A revocation signed by anyone else is refused")
    func refusesForeignRevocation() throws {
        var enrolled = try enrol()
        let impostor = Identity.generate()

        #expect(throws: CryptoError.participantMismatch) {
            try enrolled.registry.revoke(
                DeviceRevocation.issue(for: enrolled.device.id, by: impostor, at: issuedAt))
        }
        #expect(enrolled.registry.isAuthorized(enrolled.device.id, at: issuedAt))
    }

    @Test("Revoking a device the registry has never seen is refused rather than recorded blindly")
    func refusesUnknownRevocation() throws {
        var enrolled = try enrol()

        #expect(throws: CryptoError.unknownDevice) {
            try enrolled.registry.revoke(
                DeviceRevocation.issue(
                    for: DeviceKeys.generate().id, by: enrolled.identity, at: issuedAt))
        }
    }

    @Test("Admitting the same certificate twice is idempotent")
    func idempotentAdmit() throws {
        var enrolled = try enrol()
        let certificate = try DeviceCertificate.issue(
            for: enrolled.device.publicKey, by: enrolled.identity, at: issuedAt)

        try enrolled.registry.admit(certificate)
        try enrolled.registry.admit(certificate)

        #expect(enrolled.registry.deviceCount == 1)
    }

    @Test("A second certificate cannot quietly move a device's key")
    func refusesKeySubstitution() throws {
        var enrolled = try enrol()
        let replacement = DeviceKeys.generate()

        var forged = try DeviceCertificate.issue(
            for: replacement.publicKey, by: enrolled.identity, at: issuedAt.addingTimeInterval(60))
        forged.device = enrolled.device.id
        forged.signature = try enrolled.identity.sign(forged.signingPayload)

        #expect(throws: CryptoError.deviceMismatch) { try enrolled.registry.admit(forged) }
        #expect(enrolled.registry.signingKey(for: enrolled.device.id) == enrolled.device.publicKey)
    }

    @Test("A revoked device cannot be re-admitted by replaying its original certificate")
    func revocationSurvivesReplay() throws {
        var enrolled = try enrol()
        let certificate = try DeviceCertificate.issue(
            for: enrolled.device.publicKey, by: enrolled.identity, at: issuedAt)
        let revokedAt = issuedAt.addingTimeInterval(3_600)

        try enrolled.registry.revoke(
            DeviceRevocation.issue(for: enrolled.device.id, by: enrolled.identity, at: revokedAt))
        try enrolled.registry.admit(certificate)

        #expect(!enrolled.registry.isAuthorized(enrolled.device.id, at: revokedAt.addingTimeInterval(1)))
    }
}
