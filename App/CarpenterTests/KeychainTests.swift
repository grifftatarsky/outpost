import CarpenterKeychain
import Foundation
import Security
import Testing

import CarpenterKit

@Suite("System keychain", .serialized)
struct SystemKeychainTests {
    private let store = SystemKeychainStore(service: "com.microgpt.carpenter.tests")

    private func scratchKey() -> KeychainKey {
        KeychainKey("test.\(UUID().uuidString)")
    }

    @Test("A stored item comes back exactly as it went in")
    func roundTrip() async throws {
        let key = scratchKey()
        defer { Task { try? await store.remove(key) } }

        let secret = Data((0..<32).map { UInt8($0) })
        try await store.set(secret, for: key, scope: .device)

        #expect(try await store.data(for: key) == secret)
    }

    @Test("A missing item reads as nothing, not as an error")
    func missingItem() async throws {
        #expect(try await store.data(for: scratchKey()) == nil)
    }

    @Test("Writing twice replaces rather than duplicating")
    func overwrite() async throws {
        let key = scratchKey()
        defer { Task { try? await store.remove(key) } }

        try await store.set(Data([1]), for: key, scope: .device)
        try await store.set(Data([2]), for: key, scope: .device)

        #expect(try await store.data(for: key) == Data([2]))
    }

    @Test("Changing scope moves the item rather than leaving two copies behind")
    func scopeChangeReplaces() async throws {
        let key = scratchKey()
        defer { Task { try? await store.remove(key) } }

        try await store.set(Data([1]), for: key, scope: .device)
        try await store.set(Data([2]), for: key, scope: .synchronized)

        #expect(try await store.data(for: key) == Data([2]))
    }

    @Test("An item kept to this device can never leave it; a synchronized one can")
    func deviceItemsNeverLeave() async throws {
        let kept = scratchKey()
        let synced = scratchKey()
        defer {
            Task {
                try? await store.remove(kept)
                try? await store.remove(synced)
            }
        }

        try await store.set(Data([1]), for: kept, scope: .device)
        try await store.set(Data([2]), for: synced, scope: .synchronized)

        #expect(
            try store.accessibility(of: kept) == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
            "a device key, a room key or the draft key would travel to another device in a backup")
        #expect(try store.accessibility(of: synced) == kSecAttrAccessibleAfterFirstUnlock as String)
    }

    @Test("An item stored before this build is moved to this device only, in place, when it is read")
    func anOlderItemIsMovedInPlace() async throws {
        let key = scratchKey()
        defer { Task { try? await store.remove(key) } }
        let older: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.microgpt.carpenter.tests",
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: Data([7, 7]),
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        #expect(SecItemAdd(older as CFDictionary, nil) == errSecSuccess, "precondition: could not write the older item")
        #expect(try store.accessibility(of: key) == kSecAttrAccessibleAfterFirstUnlock as String)

        #expect(try await store.data(for: key) == Data([7, 7]), "reading the older item lost it")
        #expect(
            try store.accessibility(of: key) == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
            "an item stored the older way was left able to leave this device")
        #expect(try await store.data(for: key) == Data([7, 7]))
    }

    @Test("Removal is idempotent")
    func removal() async throws {
        let key = scratchKey()
        try await store.set(Data([1]), for: key, scope: .device)

        try await store.remove(key)
        try await store.remove(key)

        #expect(try await store.data(for: key) == nil)
    }

    @Test("An identity survives a round trip through the real Keychain")
    func identityPersists() async throws {
        let keychain = SystemKeychainStore(service: "com.microgpt.carpenter.tests.identity.\(UUID().uuidString)")
        let store = IdentityStore(keychain: keychain)

        let first = try await store.enrol()
        let second = try await IdentityStore(keychain: keychain).enrol()

        #expect(first.identity.id == second.identity.id)
        #expect(first.device.id == second.device.id)

        #expect(!first.deviceIsNew, "the founding device is not a second device")
        #expect(!second.deviceIsNew, "re-enrolling the same device is not a new device either")

        try await keychain.remove(IdentityStore.identityKey)
        try await keychain.remove(IdentityStore.deviceKey)
    }

    @Test("A device that finds an identity it did not mint reports itself new")
    func siblingIsNew() async throws {
        let keychain = SystemKeychainStore(
            service: "com.microgpt.carpenter.tests.sibling.\(UUID().uuidString)")
        let founding = try await IdentityStore(keychain: keychain).enrol()

        try await keychain.remove(IdentityStore.deviceKey)
        let sibling = try await IdentityStore(keychain: keychain).enrol()

        #expect(sibling.identity.id == founding.identity.id, "the identity is the member's, and shared")
        #expect(sibling.device.id != founding.device.id, "a device key is per device and never travels")
        #expect(sibling.deviceIsNew, "this is exactly the case the flag is for")

        try await keychain.remove(IdentityStore.identityKey)
        try await keychain.remove(IdentityStore.deviceKey)
    }
}
