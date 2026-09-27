import CarpenterKit
import Foundation
import LocalAuthentication
import SwiftUI

public protocol Biometrics: Sendable {
    var name: String? { get }
    func state() -> Data?
    func evaluate(reason: String) async -> Bool
}

public struct SystemBiometrics: Biometrics {
    public init() {}

    public var name: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return nil
        }
    }

    public func state() -> Data? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        return context.domainState.biometry.stateHash
    }

    public func evaluate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason))
            ?? false
    }
}

@MainActor
@Observable
public final class AppLockController {
    public private(set) var lock: AppLock?
    public private(set) var isLocked = false
    public private(set) var isCovered = false
    public private(set) var problem: AppLockProblem?
    public private(set) var checking = false
    public private(set) var loaded = false
    public private(set) var unreadable = false

    private let store: AppLockStore
    private let biometrics: any Biometrics
    private let moment: @Sendable () -> LockMoment
    private let clock: @Sendable () -> Date
    private var leftAt: LockMoment?
    private var confirmedAt: LockMoment?
    private var writing: Task<Void, Never>?

    public static let confirmationLasts: TimeInterval = 300

    public init(
        store: AppLockStore, biometrics: any Biometrics = SystemBiometrics(),
        moment: @escaping @Sendable () -> LockMoment = LockMoment.now,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.biometrics = biometrics
        self.moment = moment
        self.clock = clock
    }

    public var biometricName: String? { biometrics.name }

    public var offersBiometrics: Bool {
        guard let lock, lock.usesBiometrics, biometrics.name != nil else { return false }
        return lock.allowsBiometrics(currentState: biometrics.state())
    }

    public var biometricsChanged: Bool {
        guard let lock, lock.usesBiometrics, biometrics.name != nil else { return false }
        return !lock.allowsBiometrics(currentState: biometrics.state())
    }

    public func load() async {
        do {
            lock = try await store.load()
            unreadable = false
            isLocked = lock != nil
        } catch {
            unreadable = true
            isLocked = true
        }
        isCovered = isLocked
        loaded = true
    }

    public func sceneChanged(to phase: ScenePhase) {
        guard let lock else {
            isCovered = unreadable
            if unreadable, phase == .active { Task { await load() } }
            return
        }
        switch phase {
        case .active:
            if let leftAt {
                let away = moment().seconds(since: leftAt) ?? .infinity
                if away >= lock.delay { isLocked = true }
            }
            self.leftAt = nil
            isCovered = isLocked
        case .background:
            if leftAt == nil { leftAt = moment() }
            isCovered = true
        default:
            isCovered = true
        }
    }

    public func unlock(with code: String) async {
        guard await check(code) else { return }
        isLocked = false
        isCovered = false
    }

    public func confirm(_ code: String) async -> Bool {
        let right = await check(code)
        if right { confirmedAt = moment() }
        return right
    }

    public var recentlyConfirmed: Bool {
        guard let confirmedAt, let since = moment().seconds(since: confirmedAt) else { return false }
        return since < Self.confirmationLasts
    }

    private func check(_ code: String) async -> Bool {
        guard var lock, !checking else { return false }
        checking = true
        defer { checking = false }

        if let wait = lock.charge(at: moment()) {
            self.lock = lock
            try? await store.save(lock)
            problem = .waitUntil(clock().addingTimeInterval(wait))
            return false
        }
        do {
            try await store.save(lock)
        } catch {
            problem = .notSaved
            return false
        }
        self.lock = lock

        let snapshot = lock
        let right = await Task.detached(priority: .userInitiated) { snapshot.matches(code) }.value
        guard right else {
            switch lock.afterAWrongCode {
            case .wrong(let left): problem = .wrong(triesBeforeAWait: left)
            case .wait(let wait): problem = .waitUntil(clock().addingTimeInterval(wait))
            case .unlocked: problem = nil
            }
            return false
        }
        lock.succeeded()
        if lock.usesBiometrics { lock.noteBiometrics(biometrics.state()) }
        self.lock = lock
        try? await store.save(lock)
        problem = nil
        return true
    }

    public func unlockWithBiometrics() async {
        guard offersBiometrics, var lock else { return }
        // COPY BEGIN d35bb503 [NEEDS HUMAN REVIEW]
        let reason = String(localized: "Unlock the app", bundle: .module)
        // COPY END d35bb503
        guard await biometrics.evaluate(reason: reason) else { return }
        guard lock.allowsBiometrics(currentState: biometrics.state()) else { return }
        lock.noteBiometricUnlock()
        self.lock = lock
        try? await store.save(lock)
        problem = nil
        isLocked = false
        isCovered = false
    }

    @discardableResult
    public func turnOn(_ new: AppLock) async -> Bool {
        guard lock == nil else { return await replace(with: new) }
        return await keep(new)
    }

    @discardableResult
    public func replace(with new: AppLock) async -> Bool {
        guard lock != nil else { return await keep(new) }
        guard spendConfirmation() else { return false }
        return await keep(new)
    }

    @discardableResult
    public func turnOff() async -> Bool {
        guard lock != nil, spendConfirmation() else { return false }
        return await keep(nil)
    }

    @discardableResult
    public func setDelay(_ delay: TimeInterval) async -> Bool {
        guard var lock else { return false }
        if delay > lock.delay, !spendConfirmation() { return false }
        lock.delay = delay
        return await keep(lock)
    }

    @discardableResult
    public func setBiometrics(_ on: Bool) async -> Bool {
        guard var lock else { return false }
        if on, !spendConfirmation() { return false }
        lock.usesBiometrics = on
        return await keep(lock)
    }

    private func spendConfirmation() -> Bool {
        guard recentlyConfirmed else {
            problem = .needsCode
            return false
        }
        confirmedAt = nil
        return true
    }

    private func keep(_ new: AppLock?) async -> Bool {
        var new = new
        if new?.usesBiometrics == true { new?.noteBiometrics(biometrics.state()) }
        let (previous, store, target) = (writing, store, new)
        let write = Task<Bool, Never> {
            await previous?.value
            do {
                if let target { try await store.save(target) } else { try await store.remove() }
                return true
            } catch {
                return false
            }
        }
        writing = Task { _ = await write.value }
        guard await write.value else {
            problem = .notSaved
            return false
        }
        lock = new  // reentrancy considered
        problem = nil
        if new == nil {
            isLocked = false
            isCovered = false
        }
        return true
    }

    public func forget() {
        unreadable = false
        lock = nil
        isLocked = false
        isCovered = false
        problem = nil
        leftAt = nil
        confirmedAt = nil
    }
}

public enum AppLockProblem: Hashable, Sendable {
    case wrong(triesBeforeAWait: Int)
    case waitUntil(Date)
    case notSaved
    case needsCode
}

extension EnvironmentValues {
    @Entry public var appLock: AppLockController?
}
