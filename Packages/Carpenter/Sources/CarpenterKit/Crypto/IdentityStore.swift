import Foundation

public struct Enrolment: Sendable {
    public let identity: Identity
    public let device: DeviceKeys

    public let deviceIsNew: Bool

    public init(identity: Identity, device: DeviceKeys, deviceIsNew: Bool) {
        self.identity = identity
        self.device = device
        self.deviceIsNew = deviceIsNew
    }
}

public actor IdentityStore {
    public static let identityKey = KeychainKey("identity.keys")
    public static let deviceKey = KeychainKey("device.signing")
    public static let removedKey = KeychainKey("device.removed")
    public static let certificateKey = KeychainKey("device.certificate")

    private static let seedLength = 32

    private let keychain: any KeychainStore

    public init(keychain: any KeychainStore) {
        self.keychain = keychain
    }

    public func enrol() async throws -> Enrolment {
        let identity: Identity
        let identityExisted: Bool
        if let existing = try await loadIdentity() {
            identity = existing
            identityExisted = true
        } else {
            identity = Identity.generate()
            try await save(identity)
            identityExisted = false
        }

        if let device = try await loadDeviceKeys() {
            return Enrolment(identity: identity, device: device, deviceIsNew: false)
        }

        let device = DeviceKeys.generate()
        try await save(device)
        return Enrolment(identity: identity, device: device, deviceIsNew: identityExisted)
    }

    public func loadIdentity() async throws -> Identity? {
        guard let data = try await keychain.data(for: Self.identityKey) else { return nil }
        guard data.count == Self.seedLength * 2 else { throw CryptoError.malformedKey }

        return try Identity(
            signingSeed: data.prefix(Self.seedLength),
            agreementSeed: data.suffix(Self.seedLength)
        )
    }

    public func save(_ identity: Identity) async throws {
        try await keychain.set(
            identity.signingSeed + identity.agreementSeed,
            for: Self.identityKey,
            scope: .synchronized
        )
    }

    public func loadDeviceKeys() async throws -> DeviceKeys? {
        guard let data = try await keychain.data(for: Self.deviceKey) else { return nil }
        return try DeviceKeys(signingSeed: data)
    }

    public func save(_ device: DeviceKeys) async throws {
        try await keychain.set(device.signingSeed, for: Self.deviceKey, scope: .device)
    }

    public func forgetDevice() async throws {
        try await keychain.remove(Self.deviceKey)
    }

    public func keepCertificate(_ certificate: DeviceCertificate) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try await keychain.set(try encoder.encode(certificate), for: Self.certificateKey, scope: .device)
    }

    public func keptCertificate() async throws -> DeviceCertificate? {
        guard let data = try await keychain.data(for: Self.certificateKey) else { return nil }
        return try? JSONDecoder().decode(DeviceCertificate.self, from: data)
    }

    public func forgetCertificate() async throws {
        try await keychain.remove(Self.certificateKey)
    }

    public func markRemoved() async throws {
        try await keychain.set(Data([1]), for: Self.removedKey, scope: .device)
    }

    public func wasRemoved() async throws -> Bool {
        try await keychain.data(for: Self.removedKey) != nil
    }

    public func clearRemoved() async throws {
        try await keychain.remove(Self.removedKey)
    }
}
