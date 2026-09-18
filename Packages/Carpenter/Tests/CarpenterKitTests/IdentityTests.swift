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

    @Test("Changing either public key changes the participant ID")
    func participantIDCoversBothKeys() {
        let first = Identity.generate()
        let second = Identity.generate()

        let mixed = IdentityPublicKeys(
            signing: first.publicKeys.signing,
            agreement: second.publicKeys.agreement
        )

        #expect(mixed.participantID != first.id)
        #expect(mixed.participantID != second.id)
    }

    @Test("An identity rebuilt from its stored bytes is the same identity")
    func seedRoundTrip() throws {
        let identity = Identity.generate()
        let restored = try Identity(
            signingSeed: identity.signingSeed, agreementSeed: identity.agreementSeed)

        #expect(restored.id == identity.id)
        #expect(restored.publicKeys == identity.publicKeys)
    }

    @Test("Seeds of the wrong length are rejected rather than silently truncated")
    func rejectsMalformedSeeds() {
        #expect(throws: CryptoError.self) {
            try Identity(signingSeed: Data([1, 2, 3]), agreementSeed: Data(repeating: 0, count: 32))
        }
        #expect(throws: CryptoError.self) {
            try Identity(signingSeed: Data(repeating: 0, count: 32), agreementSeed: Data([1]))
        }
    }

    @Test("An identity built from fixed bytes is reproducible, so tests can pin one")
    func deterministicFromSeed() throws {
        let seedA = Data(repeating: 7, count: 32)
        let seedB = Data(repeating: 9, count: 32)

        let first = try Identity(signingSeed: seedA, agreementSeed: seedB)
        let second = try Identity(signingSeed: seedA, agreementSeed: seedB)

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
}
