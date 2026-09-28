import CommonCrypto
import CryptoKit
import Foundation

public struct LockMoment: Hashable, Sendable, Codable {
    public var boot: String?
    public var uptime: TimeInterval

    public init(boot: String?, uptime: TimeInterval) {
        self.boot = boot
        self.uptime = uptime
    }

    public static func now() -> LockMoment {
        LockMoment(boot: bootSession(), uptime: Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000)
    }

    public func seconds(since earlier: LockMoment) -> TimeInterval? {
        guard boot == earlier.boot, uptime >= earlier.uptime else { return nil }
        return uptime - earlier.uptime
    }

    private static func bootSession() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

public struct AppLock: Hashable, Sendable, Codable {
    public enum Code: String, Hashable, Sendable, Codable {
        case digits
        case passphrase
    }

    public var code: Code
    public var usesBiometrics: Bool
    public var biometricState: Data?
    public var delay: TimeInterval
    public var eraseAfter: Int?
    public var length: Int?
    var salt: Data
    var verifier: Data
    var rounds: Int
    public private(set) var failures: Int = 0
    public private(set) var waitStarted: LockMoment?
    public private(set) var waitLength: TimeInterval = 0

    public static let rounds = 300_000
    public static let delays: [TimeInterval] = [0, 60, 300, 900]
    public static let eraseChoices: [Int?] = [nil, 1, 5, 10]

    public var codesLeftBeforeErasing: Int? {
        eraseAfter.map { max(0, $0 - failures) }
    }

    public static func make(
        _ code: String, as kind: Code, usesBiometrics: Bool, biometricState: Data? = nil, delay: TimeInterval = 0,
        rounds: Int = AppLock.rounds
    ) throws -> AppLock {
        guard isAcceptable(code, as: kind) else { throw AppLockError.notAcceptable }
        let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return AppLock(
            code: kind, usesBiometrics: usesBiometrics, biometricState: biometricState, delay: delay,
            length: kind == .digits ? code.count : nil, salt: salt,
            verifier: derive(code, salt: salt, rounds: rounds), rounds: rounds)
    }

    public static func isAcceptable(_ code: String, as kind: Code) -> Bool {
        switch kind {
        case .digits:
            (4...6).contains(code.count) && code.allSatisfy { $0.isASCII && $0.isNumber }
        case .passphrase:
            code.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
        }
    }

    public enum Attempt: Hashable, Sendable {
        case unlocked
        case wrong(triesBeforeAWait: Int)
        case wait(TimeInterval)
    }

    public mutating func charge(at now: LockMoment) -> TimeInterval? {
        if let waitStarted, waitLength > 0 {
            if let elapsed = now.seconds(since: waitStarted) {
                if elapsed < waitLength { return waitLength - elapsed }
            } else {
                self.waitStarted = now
                return waitLength
            }
        }
        failures += 1
        let wait = Self.wait(after: failures)
        if wait > 0 {
            waitStarted = now
            waitLength = wait
        }
        return nil
    }

    public func remainingWait(at now: LockMoment) -> TimeInterval {
        guard let waitStarted, waitLength > 0 else { return 0 }
        guard let elapsed = now.seconds(since: waitStarted) else { return waitLength }
        return max(0, waitLength - elapsed)
    }

    public func matches(_ code: String) -> Bool {
        Self.same(Self.derive(code, salt: salt, rounds: rounds), verifier)
    }

    public mutating func succeeded() {
        failures = 0
        waitStarted = nil
        waitLength = 0
    }

    public var afterAWrongCode: Attempt {
        Self.wait(after: failures) > 0 ? .wait(waitLength) : .wrong(triesBeforeAWait: Self.freeTries - failures)
    }

    public mutating func unlock(with code: String, at now: LockMoment) -> Attempt {
        if let wait = charge(at: now) { return .wait(wait) }
        guard matches(code) else { return afterAWrongCode }
        succeeded()
        return .unlocked
    }

    public func allowsBiometrics(currentState: Data?) -> Bool {
        usesBiometrics && biometricState != nil && currentState == biometricState
    }

    public mutating func noteBiometrics(_ state: Data?) {
        biometricState = state
    }

    public mutating func noteBiometricUnlock() {
        succeeded()
    }

    static let freeTries = 5

    static func wait(after failures: Int) -> TimeInterval {
        switch failures {
        case ..<freeTries: 0
        case freeTries: 60
        case freeTries + 1: 300
        case freeTries + 2: 900
        default: 3600
        }
    }

    static func derive(_ code: String, salt: Data, rounds: Int) -> Data {
        let password = Array(code.precomposedStringWithCanonicalMapping.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            password.withUnsafeBufferPointer { passwordBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                    passwordBytes.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds),
                    &derived, derived.count)
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 refused its own arguments")
        return Data(derived)
    }

    static func same(_ left: Data, _ right: Data) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

public enum AppLockError: Error, Hashable, Sendable {
    case notAcceptable
}

public actor AppLockStore {
    public static let key = KeychainKey("app.lock")

    private let keychain: any KeychainStore

    public init(keychain: any KeychainStore) {
        self.keychain = keychain
    }

    public func load() async throws -> AppLock? {
        guard let data = try await keychain.data(for: Self.key) else { return nil }
        return try JSONDecoder().decode(AppLock.self, from: data)
    }

    public func save(_ lock: AppLock) async throws {
        try await keychain.set(try JSONEncoder().encode(lock), for: Self.key, scope: .device)
    }

    public func remove() async throws {
        try await keychain.remove(Self.key)
    }
}
