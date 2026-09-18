import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Identity storage")
struct IdentityStoreTests {
    @Test("First run creates an identity and a device key, and is not a new device")
    func firstRun() async throws {
        let keychain = InMemoryKeychainStore()
        let store = IdentityStore(keychain: keychain)

        let enrolment = try await store.enrol()

        #expect(!enrolment.deviceIsNew)
        #expect(enrolment.identity.id == enrolment.identity.publicKeys.participantID)
    }

    @Test("A second run returns the same identity and the same device, not new ones")
    func stableAcrossRuns() async throws {
        let keychain = InMemoryKeychainStore()

        let first = try await IdentityStore(keychain: keychain).enrol()
        let second = try await IdentityStore(keychain: keychain).enrol()

        #expect(first.identity.id == second.identity.id)
        #expect(first.device.id == second.device.id)
        #expect(!second.deviceIsNew)
    }

    @Test("The identity syncs and the device subkey does not")
    func storageScopes() async throws {
        let keychain = InMemoryKeychainStore()

        _ = try await IdentityStore(keychain: keychain).enrol()

        #expect(await keychain.scope(for: IdentityStore.identityKey) == .synchronized)
        #expect(await keychain.scope(for: IdentityStore.deviceKey) == .device)
    }

    @Test("An identity that arrived by sync still leaves the device needing to be certified")
    func syncedIdentityNewDevice() async throws {
        let original = InMemoryKeychainStore()
        let enrolment = try await IdentityStore(keychain: original).enrol()

        let replacement = InMemoryKeychainStore()
        for (key, value) in await original.synchronizedItems {
            try await replacement.set(value, for: key, scope: .synchronized)
        }

        let second = try await IdentityStore(keychain: replacement).enrol()

        #expect(second.identity.id == enrolment.identity.id)
        #expect(second.device.id != enrolment.device.id)
        #expect(second.deviceIsNew)
    }

    @Test("Stored key material round-trips exactly")
    func roundTrip() async throws {
        let keychain = InMemoryKeychainStore()
        let store = IdentityStore(keychain: keychain)
        let identity = Identity.generate()

        try await store.save(identity)
        let loaded = try await store.loadIdentity()

        #expect(loaded?.signingSeed == identity.signingSeed)
        #expect(loaded?.agreementSeed == identity.agreementSeed)
    }

    @Test("Nothing stored means nothing loaded, rather than an empty identity")
    func emptyStore() async throws {
        let store = IdentityStore(keychain: InMemoryKeychainStore())

        #expect(try await store.loadIdentity() == nil)
        #expect(try await store.loadDeviceKeys() == nil)
    }

    @Test("Corrupted key material is refused rather than used")
    func rejectsCorruptedMaterial() async throws {
        let keychain = InMemoryKeychainStore()
        try await keychain.set(Data([1, 2, 3]), for: IdentityStore.identityKey, scope: .synchronized)

        await #expect(throws: CryptoError.malformedKey) {
            try await IdentityStore(keychain: keychain).loadIdentity()
        }
    }

    @Test("Forgetting the device leaves the identity intact — Design Decision P4's self-signed device reset")
    func forgetDevice() async throws {
        let keychain = InMemoryKeychainStore()
        let store = IdentityStore(keychain: keychain)
        let enrolment = try await store.enrol()

        try await store.forgetDevice()

        #expect(try await store.loadIdentity()?.id == enrolment.identity.id)
        #expect(try await store.loadDeviceKeys() == nil)
    }
}
