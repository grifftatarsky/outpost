import CarpenterKit
import Foundation
import Security

public struct SystemKeychainStore: KeychainStore {
    private let service: String
    private let accessGroup: String?

    public init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func data(for key: KeychainKey) async throws -> Data? {
        if let found = try read(key, in: accessGroup) { return found.data }

        guard accessGroup != nil, let legacy = try read(key, in: nil) else { return nil }
        let scope: KeychainScope = legacy.synchronized ? .synchronized : .device
        try await set(legacy.data, for: key, scope: scope)
        if let group = legacy.group, group != accessGroup {
            delete(key, in: group, synchronized: legacy.synchronized)
        }
        return legacy.data
    }

    static func accessibility(for scope: KeychainScope) -> CFString {
        switch scope {
        case .device: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .synchronized: kSecAttrAccessibleAfterFirstUnlock
        }
    }

    private struct Found {
        let data: Data
        let synchronized: Bool
        let group: String?
    }

    private func read(_ key: KeychainKey, in group: String?) throws -> Found? {
        var query = match(key, in: group, synchronized: nil)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let item = result as? [String: Any],
                let data = item[kSecValueData as String] as? Data
            else { return nil }
            let found = Found(
                data: data,
                synchronized: (item[kSecAttrSynchronizable as String] as? Bool) ?? false,
                group: item[kSecAttrAccessGroup as String] as? String)
            let accessible = item[kSecAttrAccessible as String] as? String
            if !found.synchronized, accessible != Self.accessibility(for: .device) as String {
                keepOnThisDevice(key, in: found.group ?? group)
            }
            return found
        case errSecItemNotFound: return nil
        case errSecMissingEntitlement, errSecNoAccessForItem: return nil
        default: throw KeychainError(status: status)
        }
    }

    public func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws {
        var group = accessGroup
        if case .refused = try write(data, for: key, scope: scope, in: group), accessGroup != nil {
            Diagnostics.sync.error(
                "keychain: the shared access group was refused; filing in the app's own group instead")
            group = nil
            guard case .wrote = try write(data, for: key, scope: scope, in: nil) else {
                throw KeychainError(status: errSecMissingEntitlement)
            }
        }
        delete(key, in: group, synchronized: scope != .synchronized)
    }

    private enum WriteOutcome { case wrote, refused }

    private func write(
        _ data: Data, for key: KeychainKey, scope: KeychainScope, in group: String?
    ) throws -> WriteOutcome {
        let target = match(key, in: group, synchronized: scope == .synchronized)
        let changes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: Self.accessibility(for: scope),
        ]

        let updated = SecItemUpdate(target as CFDictionary, changes as CFDictionary)
        switch updated {
        case errSecSuccess: return .wrote
        case errSecItemNotFound: break
        case errSecMissingEntitlement, errSecNoAccessForItem: return .refused
        default: throw KeychainError(status: updated)
        }

        let added = SecItemAdd(target.merging(changes) { $1 } as CFDictionary, nil)
        switch added {
        case errSecSuccess: return .wrote
        case errSecMissingEntitlement, errSecNoAccessForItem: return .refused
        default: throw KeychainError(status: added)
        }
    }

    private func keepOnThisDevice(_ key: KeychainKey, in group: String?) {
        let changes = [kSecAttrAccessible as String: Self.accessibility(for: .device)]
        let status = SecItemUpdate(
            match(key, in: group, synchronized: false) as CFDictionary, changes as CFDictionary)
        if status != errSecSuccess {
            Diagnostics.sync.error(
                "keychain: could not keep an item on this device only (\(status, privacy: .public))")
        }
    }

    private func delete(_ key: KeychainKey, in group: String?, synchronized: Bool) {
        SecItemDelete(match(key, in: group, synchronized: synchronized) as CFDictionary)
    }

    public func remove(_ key: KeychainKey) async throws {
        let status = SecItemDelete(match(key, in: accessGroup, synchronized: nil) as CFDictionary)
        guard
            status == errSecSuccess || status == errSecItemNotFound
                || status == errSecMissingEntitlement || status == errSecNoAccessForItem
        else {
            throw KeychainError(status: status)
        }

        if accessGroup != nil {
            SecItemDelete(match(key, in: nil, synchronized: nil) as CFDictionary)
        }
    }

    public func removeAll() async throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func match(_ key: KeychainKey, in group: String?, synchronized: Bool?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: synchronized.map { $0 as Any } ?? kSecAttrSynchronizableAny,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }
}

public enum SharedKeychain {
    public static let name = "com.microgpt.carpenter.shared"

    public static let group: String? = {
        guard let prefix = teamPrefix else { return nil }
        let candidate = prefix + name

        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "carpenter.shared-group-probe",
            kSecAttrAccount as String: "carpenter.shared-group-probe",
            kSecAttrAccessGroup as String: candidate,
            kSecUseDataProtectionKeychain as String: true,
        ]

        let status = SecItemAdd(probe as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { return nil }
        SecItemDelete(probe as CFDictionary)
        return candidate
    }()

    private static let teamPrefix: String? = {
        let probe = "carpenter.access-group-probe"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probe,
            kSecAttrAccount as String: probe,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnAttributes as String: true,
        ]

        var result: CFTypeRef?
        var status = SecItemAdd(query as CFDictionary, &result)
        if status == errSecDuplicateItem {
            var lookup = query
            lookup[kSecReturnAttributes as String] = true
            status = SecItemCopyMatching(lookup as CFDictionary, &result)
        }
        guard status == errSecSuccess,
            let attributes = result as? [String: Any],
            let group = attributes[kSecAttrAccessGroup as String] as? String,
            let dot = group.firstIndex(of: ".")
        else { return nil }

        SecItemDelete(query as CFDictionary)
        return String(group[...dot])
    }()
}

public struct KeychainError: Error, Hashable, Sendable {
    public let status: OSStatus

    public var message: String {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}
