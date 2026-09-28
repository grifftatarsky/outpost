import Foundation

public struct TestProfile: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var server: URL
    public var syncsToOtherDevices: Bool

    public init(id: UUID = UUID(), name: String, server: URL, syncsToOtherDevices: Bool = false) {
        self.id = id
        self.name = name
        self.server = server
        self.syncsToOtherDevices = syncsToOtherDevices
    }

    public func container(within base: String) -> String {
        "\(base).test-\(id.uuidString.lowercased())"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, server, syncsToOtherDevices
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        server = try values.decode(URL.self, forKey: .server)
        syncsToOtherDevices = try values.decodeIfPresent(Bool.self, forKey: .syncsToOtherDevices) ?? false
    }
}

public struct TestProfiles: Codable, Equatable, Sendable {
    public private(set) var profiles: [TestProfile]
    public private(set) var activeID: UUID?

    public init(profiles: [TestProfile] = [], activeID: UUID? = nil) {
        self.profiles = profiles
        self.activeID = profiles.contains { $0.id == activeID } ? activeID : nil
    }

    public var active: TestProfile? {
        profiles.first { $0.id == activeID }
    }

    public mutating func add(_ profile: TestProfile) {
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
    }

    public mutating func remove(_ id: UUID) {
        guard id != activeID else { return }
        profiles.removeAll { $0.id == id }
    }

    public mutating func activate(_ id: UUID?) {
        activeID = profiles.contains { $0.id == id } ? id : nil
    }

    private enum CodingKeys: String, CodingKey {
        case profiles, activeID
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            profiles: try values.decodeIfPresent([TestProfile].self, forKey: .profiles) ?? [],
            activeID: try values.decodeIfPresent(UUID.self, forKey: .activeID))
    }
}

public enum TestProfileProblem: Error, Equatable, Sendable {
    case serverNotSupported
    case serverUnreachable
    case listNotSaved
}

public struct TestProfileStore: Sendable {
    public static let fileName = "test-profiles.json"

    public let url: URL

    public init(directory: URL) {
        url = directory.appending(path: Self.fileName)
    }

    public func load() -> TestProfiles {
        guard let data = try? Data(contentsOf: url) else { return TestProfiles() }
        do {
            return try JSONDecoder().decode(TestProfiles.self, from: data)
        } catch {
            setAside(data)
            return TestProfiles()
        }
    }

    public var isAnyProfileActive: Bool {
        guard let data = try? Data(contentsOf: url),
            let profiles = try? JSONDecoder().decode(TestProfiles.self, from: data)
        else { return false }
        return profiles.active != nil
    }

    public func save(_ profiles: TestProfiles) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(profiles).write(to: url, options: .atomic)
    }

    public var setAsideURLs: [URL] {
        let directory = url.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.hasPrefix(Self.fileName + ".unreadable-") }
            .sorted()
            .map { directory.appending(path: $0) }
    }

    private func setAside(_ data: Data) {
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = url.deletingLastPathComponent()
            .appending(path: "\(Self.fileName).unreadable-\(stamp)-\(UUID().uuidString.prefix(8))")
        do {
            try data.write(to: aside, options: .atomic)
            try FileManager.default.removeItem(at: url)
            Diagnostics.sync.error(
                "test profiles: the list could not be read; set aside at \(aside.lastPathComponent, privacy: .public)")
        } catch {
            Diagnostics.sync.error(
                "test profiles: the list could not be read or set aside (\(String(describing: error), privacy: .public))")
        }
    }
}

public struct DeviceOnlyKeychainStore: KeychainStore {
    private let inner: any KeychainStore

    public init(_ inner: any KeychainStore) {
        self.inner = inner
    }

    public func data(for key: KeychainKey) async throws -> Data? {
        try await inner.data(for: key)
    }

    public func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws {
        try await inner.set(data, for: key, scope: .device)
    }

    public func remove(_ key: KeychainKey) async throws {
        try await inner.remove(key)
    }

    public func removeAll() async throws {
        try await inner.removeAll()
    }

    public func protect(as protection: StorageProtection) async throws {
        try await inner.protect(as: protection)
    }
}
