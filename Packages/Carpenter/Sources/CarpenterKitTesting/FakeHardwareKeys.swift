import CarpenterKit
import CryptoKit
import Foundation

public actor FakeHardwareKeys: HardwareKeys {
    private var keys: [HardwareKeyID: P256.KeyAgreement.PrivateKey] = [:]
    private var needsBiometrics: Set<HardwareKeyID> = []

    public private(set) var agreements = 0
    public private(set) var biometricChecks = 0

    public var biometricsSucceed = true
    public var isAvailable = true

    public init() {}

    public func allowBiometrics(_ allowed: Bool) { biometricsSucceed = allowed }

    public func makeUnavailable() { isAvailable = false }

    public func forgetEverything() {
        keys = [:]
        needsBiometrics = []
    }

    public func make(_ id: HardwareKeyID, requiringBiometrics: Bool) async throws -> Data {
        guard isAvailable else { throw HardwareKeyError.unavailable }
        let key = P256.KeyAgreement.PrivateKey()
        keys[id] = key
        if requiringBiometrics { needsBiometrics.insert(id) } else { needsBiometrics.remove(id) }
        return key.publicKey.x963Representation
    }

    public func publicKey(of id: HardwareKeyID) async throws -> Data? {
        keys[id]?.publicKey.x963Representation
    }

    public func agree(_ id: HardwareKeyID, with publicKey: Data, reason: String) async throws -> Data {
        guard isAvailable else { throw HardwareKeyError.unavailable }
        guard let key = keys[id] else { throw HardwareKeyError.noSuchKey }
        if needsBiometrics.contains(id) {
            biometricChecks += 1
            guard biometricsSucceed else { throw HardwareKeyError.refused }
        }
        agreements += 1
        let theirs = try P256.KeyAgreement.PublicKey(x963Representation: publicKey)
        return try key.sharedSecretFromKeyAgreement(with: theirs).withUnsafeBytes { Data($0) }
    }

    public func remove(_ id: HardwareKeyID) async throws {
        keys[id] = nil
        needsBiometrics.remove(id)
    }
}
