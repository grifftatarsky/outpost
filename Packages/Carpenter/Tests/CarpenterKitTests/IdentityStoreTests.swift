import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Identity storage")
struct IdentityStoreTests {
    private func stored(in keychain: InMemoryKeychainStore) async throws -> Identity {
        let identity = RecoverySecret.generate().identity
        try await IdentityStore(keychain: keychain).save(identity)
        return identity
    }

    @Test("Enrolling never makes an identity up; without one it refuses")
    func enrollingNeedsAnIdentity() async throws {
        let keychain = InMemoryKeychainStore()
        await #expect(throws: CryptoError.noIdentity) { try await IdentityStore(keychain: keychain).enrol() }
        #expect(try await IdentityStore(keychain: keychain).loadIdentity() == nil)
    }

    @Test("A device enrolling with a stored identity gets its own key once, and keeps it")
    func stableAcrossRuns() async throws {
        let keychain = InMemoryKeychainStore()
        let identity = try await stored(in: keychain)

        let first = try await IdentityStore(keychain: keychain).enrol()
        let second = try await IdentityStore(keychain: keychain).enrol()

        #expect(first.identity == identity)
        #expect(first.identity.recovery == nil, "the recovery key was kept with the identity")
        #expect(first.deviceIsNew)
        #expect(first.identity.id == second.identity.id)
        #expect(first.device.id == second.device.id)
        #expect(!second.deviceIsNew)
    }

    @Test("Neither the identity nor the device key goes to iCloud Keychain")
    func storageScopes() async throws {
        let keychain = InMemoryKeychainStore()
        _ = try await stored(in: keychain)
        _ = try await IdentityStore(keychain: keychain).enrol()

        #expect(await keychain.scope(for: IdentityStore.identityKey) == .device)
        #expect(await keychain.scope(for: IdentityStore.deviceKey) == .device)
        #expect(await keychain.synchronizedItems.isEmpty)
        #expect(try await IdentityStore(keychain: await keychain.sibling()).loadIdentity() == nil)
    }

    @Test("Stored key material round-trips exactly, recovery key included")
    func roundTrip() async throws {
        let keychain = InMemoryKeychainStore()
        let identity = try await stored(in: keychain)
        let loaded = try await IdentityStore(keychain: keychain).loadIdentity()

        #expect(loaded?.signingSeed == identity.signingSeed)
        #expect(loaded?.agreementSeed == identity.agreementSeed)
        #expect(loaded?.publicKeys.recovery == identity.publicKeys.recovery)
        #expect(loaded?.id == identity.id)
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
        try await keychain.set(Data([1, 2, 3]), for: IdentityStore.identityKey, scope: .device)

        await #expect(throws: CryptoError.malformedKey) {
            try await IdentityStore(keychain: keychain).loadIdentity()
        }
    }

    @Test("An identity from before the recovery key changed is named as such, not used")
    func anOldIdentityIsRetired() async throws {
        let keychain = InMemoryKeychainStore()
        try await keychain.set(Data(repeating: 7, count: 64), for: IdentityStore.identityKey, scope: .synchronized)

        await #expect(throws: CryptoError.retiredIdentity) {
            try await IdentityStore(keychain: keychain).loadIdentity()
        }
    }

    @Test("The unsaved recovery key is kept until it is forgotten, and then it is gone")
    func theUnsavedKeyIsForgotten() async throws {
        let keychain = InMemoryKeychainStore()
        let store = IdentityStore(keychain: keychain)
        let recovery = RecoverySecret.generate()

        try await store.keepUnsaved(recovery)
        #expect(try await store.unsavedRecoveryKey() == recovery)
        #expect(await keychain.scope(for: IdentityStore.unsavedRecoveryKey) == .device)

        try await store.forgetUnsavedRecoveryKey()
        #expect(try await store.unsavedRecoveryKey() == nil)
        #expect(try await keychain.data(for: IdentityStore.unsavedRecoveryKey) == nil)
    }

    @Test("Forgetting the device leaves the identity intact")
    func forgetDevice() async throws {
        let keychain = InMemoryKeychainStore()
        let store = IdentityStore(keychain: keychain)
        let identity = try await stored(in: keychain)
        _ = try await store.enrol()

        try await store.forgetDevice()

        #expect(try await store.loadIdentity()?.id == identity.id)
        #expect(try await store.loadDeviceKeys() == nil)
    }
}
