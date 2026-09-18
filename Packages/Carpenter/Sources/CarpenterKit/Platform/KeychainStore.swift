import Foundation

public struct KeychainKey: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum KeychainScope: Hashable, Sendable {
    case device
    case synchronized
}

public protocol KeychainStore: Sendable {
    func data(for key: KeychainKey) async throws -> Data?
    func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws
    func remove(_ key: KeychainKey) async throws

    func removeAll() async throws
}
