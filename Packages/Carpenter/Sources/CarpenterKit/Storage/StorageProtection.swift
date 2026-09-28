import Foundation
import Synchronization

public enum StorageProtection: String, Hashable, Sendable, Codable {
    case afterFirstUnlock
    case whileUnlocked

    public var fileProtection: FileProtectionType {
        switch self {
        case .afterFirstUnlock: .completeUntilFirstUserAuthentication
        case .whileUnlocked: .complete
        }
    }

    public var writingOption: Data.WritingOptions {
        switch self {
        case .afterFirstUnlock: .completeFileProtectionUntilFirstUserAuthentication
        case .whileUnlocked: .completeFileProtection
        }
    }

    public var fileAttributes: [FileAttributeKey: Any] { [.protectionKey: fileProtection] }
}

public final class ProtectionDial: Sendable {
    private let setting: Mutex<StorageProtection>

    public init(_ protection: StorageProtection = .afterFirstUnlock) {
        setting = Mutex(protection)
    }

    public var current: StorageProtection { setting.withLock { $0 } }

    public func turn(to protection: StorageProtection) {
        setting.withLock { $0 = protection }
    }
}

public struct ProtectionChoice: Hashable, Sendable, Codable {
    public var chosen: StorageProtection
    public var applied: StorageProtection?

    public init(chosen: StorageProtection, applied: StorageProtection?) {
        self.chosen = chosen
        self.applied = applied
    }

    public static let key = KeychainKey("storage.protection")

    public static let unset = ProtectionChoice(chosen: .afterFirstUnlock, applied: nil)

    public var isApplied: Bool { applied == chosen }

    public enum Reading: Hashable, Sendable {
        case read(ProtectionChoice)
        case unreadable
    }

    public static func read(from keychain: any KeychainStore) async -> Reading {
        let stored: Data?
        do {
            stored = try await keychain.data(for: key)
        } catch {
            return .unreadable
        }
        guard let stored else { return .read(.unset) }
        guard let choice = try? JSONDecoder().decode(ProtectionChoice.self, from: stored) else { return .unreadable }
        return .read(choice)
    }

    public func write(to keychain: any KeychainStore) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try await keychain.set(try encoder.encode(self), for: Self.key, scope: .device)
    }
}

public enum ProtectedFiles {
    public static func write(
        _ data: Data, to url: URL, as protection: StorageProtection, using fileManager: FileManager = .default
    ) throws {
        try data.write(to: url, options: [.atomic, protection.writingOption])
        try fileManager.setAttributes(protection.fileAttributes, ofItemAtPath: url.path)
    }

    public static func reprotect(
        _ locations: [URL], as protection: StorageProtection, using fileManager: FileManager = .default
    ) -> [URL] {
        var refused: [URL] = []
        for item in locations.flatMap({ everything(at: $0, using: fileManager) }) {
            do {
                try fileManager.setAttributes(protection.fileAttributes, ofItemAtPath: item.path)
            } catch {
                refused.append(item)
            }
        }
        return refused
    }

    private static func everything(at location: URL, using fileManager: FileManager) -> [URL] {
        guard fileManager.fileExists(atPath: location.path) else { return [] }
        let within = fileManager.enumerator(at: location, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        return [location] + within
    }
}
