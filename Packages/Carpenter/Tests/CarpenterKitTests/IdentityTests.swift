import CryptoKit
import Foundation
import Testing

@testable import CarpenterKit

@Suite("Identity and device keys")
struct IdentityTests {
    @Test("A generated identity has both a signing and an agreement key")
    func generation() throws {
        let identity = Identity.generate()

        #expect(identity.publicKeys.signing.count == 32)
        #expect(identity.publicKeys.agreement.count == 32)
        #expect(try identity.sign(Data("hello".utf8)).count == 64)
    }

    @Test("Two generated identities are different")
    func uniqueness() {
        #expect(Identity.generate().id != Identity.generate().id)
    }

    @Test("A participant ID is a function of the public keys, so every device derives the same one")
    func participantIDIsDerived() throws {
        let identity = Identity.generate()
        let asOthersSeeIt = identity.publicKeys

        #expect(asOthersSeeIt.participantID == identity.id)
        #expect(identity.id.rawValue.count == 32)
    }

    @Test("Changing any of the three public keys changes the participant ID")
    func participantIDCoversEveryKey() {
        let first = Identity.generate().publicKeys
        let second = Identity.generate().publicKeys

        let mixes = [
            IdentityPublicKeys(signing: second.signing, agreement: first.agreement, recovery: first.recovery),
            IdentityPublicKeys(signing: first.signing, agreement: second.agreement, recovery: first.recovery),
            IdentityPublicKeys(signing: first.signing, agreement: first.agreement, recovery: second.recovery),
        ]
        for mixed in mixes {
            #expect(mixed.participantID != first.participantID)
            #expect(mixed.participantID != second.participantID)
        }
        #expect(Set(mixes.map(\.participantID)).count == 3)
    }

    @Test("An identity rebuilt from its stored bytes is the same identity")
    func seedRoundTrip() throws {
        let identity = Identity.generate()
        let restored = try Identity(
            signingSeed: identity.signingSeed, agreementSeed: identity.agreementSeed,
            recoveryKey: identity.publicKeys.recovery)

        #expect(restored.id == identity.id)
        #expect(restored.publicKeys == identity.publicKeys)
    }

    @Test("Seeds of the wrong length are rejected rather than silently truncated")
    func rejectsMalformedSeeds() {
        let recovery = RecoverySecret.generate().publicKey
        #expect(throws: CryptoError.self) {
            try Identity(signingSeed: Data([1, 2, 3]), agreementSeed: Data(repeating: 0, count: 32), recoveryKey: recovery)
        }
        #expect(throws: CryptoError.self) {
            try Identity(signingSeed: Data(repeating: 0, count: 32), agreementSeed: Data([1]), recoveryKey: recovery)
        }
        #expect(throws: CryptoError.self) {
            try Identity(
                signingSeed: Data(repeating: 0, count: 32), agreementSeed: Data(repeating: 1, count: 32),
                recoveryKey: Data([1, 2]))
        }
    }

    @Test("An identity built from fixed bytes is reproducible, so tests can pin one")
    func deterministicFromSeed() throws {
        let seedA = Data(repeating: 7, count: 32)
        let seedB = Data(repeating: 9, count: 32)

        let recovery = Data(repeating: 3, count: 32)
        let first = try Identity(signingSeed: seedA, agreementSeed: seedB, recoveryKey: recovery)
        let second = try Identity(signingSeed: seedA, agreementSeed: seedB, recoveryKey: recovery)

        #expect(first.id == second.id)
    }

    @Test("A signature verifies under the signer's public key and nothing else")
    func signatureVerification() throws {
        let identity = Identity.generate()
        let other = Identity.generate()
        let message = Data("the mooring mast drawings are 1:200".utf8)

        let signature = try identity.sign(message)

        #expect(try identity.publicKeys.isValidSignature(signature, for: message))
        #expect(try !other.publicKeys.isValidSignature(signature, for: message))
        #expect(try !identity.publicKeys.isValidSignature(signature, for: Data("tampered".utf8)))
    }

    @Test("Device keys are their own signing key with an ID derived from it")
    func deviceKeyGeneration() throws {
        let device = DeviceKeys.generate()

        #expect(device.publicKey.count == 32)
        #expect(device.id.rawValue.count == 32)
        #expect(device.id == DeviceID(publicKey: device.publicKey))
    }

    @Test("Two devices of the same member have different device IDs")
    func devicesAreDistinct() {
        #expect(DeviceKeys.generate().id != DeviceKeys.generate().id)
    }

    @Test("A device signs with its own subkey, not with the identity key")
    func deviceSigning() throws {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        let message = Data("entry".utf8)

        let signature = try device.sign(message)

        #expect(try DeviceKeys.isValidSignature(signature, for: message, publicKey: device.publicKey))
        #expect(try !identity.publicKeys.isValidSignature(signature, for: message))
    }

    @Test("An identity's keys and ID are the ones its seeds derive, however it was made")
    func identityDerivesFromItsSeeds() throws {
        let generated = Identity.generate()
        let reread = try Identity(
            signingSeed: generated.signingSeed, agreementSeed: generated.agreementSeed,
            recoveryKey: generated.publicKeys.recovery)

        let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: generated.signingSeed)
        let agreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: generated.agreementSeed)
        let derived = IdentityPublicKeys(
            signing: signing.publicKey.rawRepresentation, agreement: agreement.publicKey.rawRepresentation,
            recovery: try #require(generated.recovery).publicKey)

        #expect(generated.publicKeys == derived)
        #expect(generated.id == derived.participantID)
        #expect(reread == generated)
        #expect(reread.id == generated.id)
    }

    @Test("A device's public key and ID are the ones its seed derives, however it was made")
    func deviceDerivesFromItsSeed() throws {
        let generated = DeviceKeys.generate()
        let reread = try DeviceKeys(signingSeed: generated.signingSeed)
        let derived = try Curve25519.Signing.PrivateKey(rawRepresentation: generated.signingSeed)
            .publicKey.rawRepresentation

        #expect(generated.publicKey == derived)
        #expect(generated.id == DeviceID(publicKey: derived))
        #expect(reread == generated)
    }

    @Test("A malformed seed is refused, not stored")
    func malformedSeedsAreRefused() {
        #expect(throws: CryptoError.self) {
            try Identity(
                signingSeed: Data([1, 2, 3]), agreementSeed: Data(count: 32),
                recoveryKey: RecoverySecret.generate().publicKey)
        }
        #expect(throws: CryptoError.self) { try DeviceKeys(signingSeed: Data([1, 2, 3])) }
    }

    @Test("A deny-list fingerprint is the lowercase hex SHA-256 of the participant ID")
    func denyListFingerprintIsPinned() {
        let person = ParticipantID(rawValue: Data(repeating: 7, count: 32))
        #expect(
            DenyList.fingerprint(of: person)
                == "4bb06f8e4e3a7715d201d573d0aa423762e55dabd61a2c02278fa56cc6d294e0")
    }

    @Test("An empty deny list holds nobody, and a listed person is held")
    func denyListMembership() {
        let person = ParticipantID(rawValue: Data(repeating: 7, count: 32))
        #expect(!DenyList.empty.contains(person))
        let listed = DenyList(version: 1, updated: "", fingerprints: [DenyList.fingerprint(of: person)])
        #expect(listed.contains(person))
        #expect(!listed.contains(ParticipantID(rawValue: Data(repeating: 8, count: 32))))
    }
}
