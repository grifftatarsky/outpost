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

    private func accessibility(
        of key: KeychainKey, synchronized: Bool, service: String = "com.microgpt.carpenter.tests"
    ) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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

    @Test("A key written the old way, which could travel in a backup, is kept on the device once the app protects what it keeps")
    func oldItemsAreKeptOnTheDevice() async throws {
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

        try await store.protect(as: .afterFirstUnlock)

        #expect(try await store.data(for: key) == Data([7]))
        #expect(accessibility(of: key, synchronized: false) == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @Test("With Advanced On Device Security on, a key is written so it opens only while the phone is unlocked")
    func sealedKeysOpenOnlyWhileUnlocked() async throws {
        let sealed = SystemKeychainStore(
            service: "com.microgpt.carpenter.tests", protection: ProtectionDial(.whileUnlocked))
        let key = scratchKey()
        defer { Task { try? await sealed.remove(key) } }

        try await sealed.set(Data([1]), for: key, scope: .device)

        #expect(accessibility(of: key, synchronized: false) == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(try await sealed.data(for: key) == Data([1]))
    }

    @Test("Changing the setting reaches every key already kept, in both directions")
    func protectingReachesEveryKey() async throws {
        let service = "com.microgpt.carpenter.tests.protect.\(UUID().uuidString)"
        let keychain = SystemKeychainStore(service: service)
        let keys = [scratchKey(), scratchKey(), scratchKey()]
        for key in keys { try await keychain.set(Data([9]), for: key, scope: .device) }
        defer { Task { try? await keychain.removeAll() } }

        try await keychain.protect(as: .whileUnlocked)
        for key in keys {
            #expect(accessibility(of: key, synchronized: false, service: service) == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        }

        try await keychain.protect(as: .afterFirstUnlock)
        for key in keys {
            #expect(accessibility(of: key, synchronized: false, service: service) == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
            #expect(try await keychain.data(for: key) == Data([9]), "protecting a key changed what it holds")
        }
    }

    @Test("Reading a key never changes how it is protected, so the notification extension cannot undo the setting")
    func readingChangesNothing() async throws {
        let sealed = SystemKeychainStore(
            service: "com.microgpt.carpenter.tests", protection: ProtectionDial(.whileUnlocked))
        let key = scratchKey()
        defer { Task { try? await sealed.remove(key) } }
        try await sealed.set(Data([5]), for: key, scope: .device)

        let reader = SystemKeychainStore(service: "com.microgpt.carpenter.tests")
        #expect(try await reader.data(for: key) == Data([5]))

        #expect(
            accessibility(of: key, synchronized: false) == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
            "a read opened a sealed key to anybody with the phone locked")
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

    @Test("An identity survives a round trip through the real Keychain, kept on this device only")
    func identityPersists() async throws {
        let service = "com.microgpt.carpenter.tests.identity.\(UUID().uuidString)"
        let keychain = SystemKeychainStore(service: service)
        let store = IdentityStore(keychain: keychain)
        let identity = RecoverySecret.generate().identity
        try await store.save(identity)

        let first = try await store.enrol(founding: true)
        let second = try await IdentityStore(keychain: keychain).enrol()

        #expect(first.identity == identity)
        #expect(first.identity.id == second.identity.id)
        #expect(first.device.id == second.device.id)
        #expect(!first.deviceIsNew, "the founding device is not a second device")
        #expect(!second.deviceIsNew, "re-enrolling the same device is not a new device either")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: IdentityStore.identityKey.rawValue,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: true,
        ]
        #expect(SecItemCopyMatching(query as CFDictionary, nil) == errSecItemNotFound, "the identity went to iCloud Keychain")
        var local = query
        local[kSecAttrSynchronizable as String] = false
        #expect(SecItemCopyMatching(local as CFDictionary, nil) == errSecSuccess, "precondition: the identity is on the device")

        try await keychain.remove(IdentityStore.identityKey)
        try await keychain.remove(IdentityStore.deviceKey)
    }

    @Test("Enrolling where no identity is kept refuses, rather than making one nobody can restore")
    func noIdentityNoEnrolment() async throws {
        let keychain = SystemKeychainStore(
            service: "com.microgpt.carpenter.tests.sibling.\(UUID().uuidString)")
        await #expect(throws: CryptoError.noIdentity) { try await IdentityStore(keychain: keychain).enrol() }
        #expect(try await IdentityStore(keychain: keychain).loadDeviceKeys() == nil)
    }
}
