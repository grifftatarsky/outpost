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

    private func accessibility(of key: KeychainKey, synchronized: Bool) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.microgpt.carpenter.tests",
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: synchronized,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return (result as? [String: Any])?[kSecAttrAccessible as String] as? String
    }

    @Test("A key kept on this device can never travel in a backup; one in iCloud Keychain is left as iCloud needs it")
    func deviceItemsStayOnTheDevice() async throws {
        let (mine, shared) = (scratchKey(), scratchKey())
        defer { Task { try? await store.remove(mine); try? await store.remove(shared) } }

        try await store.set(Data([1]), for: mine, scope: .device)
        try await store.set(Data([2]), for: shared, scope: .synchronized)

        #expect(accessibility(of: mine, synchronized: false) == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(accessibility(of: shared, synchronized: true) == kSecAttrAccessibleAfterFirstUnlock as String)
    }

    @Test("A key written the old way, which could travel in a backup, is kept on the device the first time it is read")
    func oldItemsAreMovedOnRead() async throws {
        let key = scratchKey()
        defer { Task { try? await store.remove(key) } }
        let old: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.microgpt.carpenter.tests",
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data([7]),
        ]
        #expect(SecItemAdd(old as CFDictionary, nil) == errSecSuccess)
        #expect(accessibility(of: key, synchronized: false) == kSecAttrAccessibleAfterFirstUnlock as String)

        #expect(try await store.data(for: key) == Data([7]))

        #expect(accessibility(of: key, synchronized: false) == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @Test("Rewriting a key replaces it in place and leaves one copy")
    func rewritingKeepsOneCopy() async throws {
        let key = scratchKey()
        defer { Task { try? await store.remove(key) } }
        try await store.set(Data([1]), for: key, scope: .device)
        try await store.set(Data([2]), for: key, scope: .device)

        let all: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.microgpt.carpenter.tests",
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(all as CFDictionary, &result) == errSecSuccess)
        #expect((result as? [[String: Any]])?.count == 1)
        #expect(try await store.data(for: key) == Data([2]))
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
