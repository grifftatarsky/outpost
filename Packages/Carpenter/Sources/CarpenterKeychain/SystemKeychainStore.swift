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
        try? await set(legacy.data, for: key, scope: legacy.synchronized ? .synchronized : .device)
        return legacy.data
    }

    private func read(
        _ key: KeychainKey, in group: String?
    ) throws -> (data: Data, synchronized: Bool)? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let item = result as? [String: Any],
                let data = item[kSecValueData as String] as? Data
            else { return nil }
            return (data, (item[kSecAttrSynchronizable as String] as? Bool) ?? false)
        case errSecItemNotFound: return nil
        case errSecMissingEntitlement, errSecNoAccessForItem: return nil
        default: throw KeychainError(status: status)
        }
    }

    public func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws {
        try await remove(key)

        if case .refused = try write(data, for: key, scope: scope, in: accessGroup),
            accessGroup != nil
        {
            Diagnostics.sync.error(
                "keychain: the shared access group was refused; filing in the app's own group instead")
            guard case .wrote = try write(data, for: key, scope: scope, in: nil) else {
                throw KeychainError(status: errSecMissingEntitlement)
            }
        }
    }

    private enum WriteOutcome { case wrote, refused }

    private func write(
        _ data: Data, for key: KeychainKey, scope: KeychainScope, in group: String?
    ) throws -> WriteOutcome {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: (scope == .synchronized),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if let group { attributes[kSecAttrAccessGroup as String] = group }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess: return .wrote
        case errSecMissingEntitlement, errSecNoAccessForItem: return .refused
        default: throw KeychainError(status: status)
        }
    }

    public func remove(_ key: KeychainKey) async throws {
        var query = baseQuery(for: key)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        let status = SecItemDelete(query as CFDictionary)
        guard
            status == errSecSuccess || status == errSecItemNotFound
                || status == errSecMissingEntitlement || status == errSecNoAccessForItem
        else {
            throw KeychainError(status: status)
        }

        if accessGroup != nil {
            let legacy: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key.rawValue,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]
            SecItemDelete(legacy as CFDictionary)
        }
    }

    public func removeAll() async throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery(for key: KeychainKey) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
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
