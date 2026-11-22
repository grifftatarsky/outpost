import CarpenterKit
import CryptoKit
import Foundation
import LocalAuthentication
import SwiftUI

public protocol Biometrics: Sendable {
    var name: String? { get }
    func state() -> Data?
    func passcodeIsSet() -> Bool
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

    public func passcodeIsSet() -> Bool {
        var error: NSError?
        let usable = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        return usable || error?.code != LAError.Code.passcodeNotSet.rawValue
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
    public private(set) var isAway = false
    public var coversWhenAway = false
    public private(set) var problem: AppLockProblem?
    public private(set) var checking = false
    public private(set) var loaded = false
    public private(set) var unreadable = false
    public private(set) var erasing = false
    public var onEraseEverywhere: (@MainActor () async -> Void)?
    public var recovery: RecoveryKeyAccess?
    public var notificationPrivacy: NotificationPrivacy?

    public var onKeptChanged: (@MainActor () async -> Bool)?
    public var onReopened: (@MainActor () async -> Bool)?
    public var vaultRecoverySecret: (@MainActor () -> Data?)?

    private let store: AppLockStore
    private let vault: VaultKeeper?
    private let biometrics: any Biometrics
    private let moment: @Sendable () -> LockMoment
    private let clock: @Sendable () -> Date
    private var leftAt: LockMoment?
    private var confirmedAt: LockMoment?
    private var writing: Task<Void, Never>?
    private var passed: PassedCheck?
    private var passedAt: LockMoment?
    private var asking: Task<PassedCheck?, Never>?
    private var checksAsked = 0
    private var sheetsUp = 0
    private var isActive = false
    private var asksWhenActive = true
    private var leftWhileASheetWasUp = false

    public static let confirmationLasts: TimeInterval = 300
    public static let checkLasts: TimeInterval = 60

    public init(
        store: AppLockStore, vault: VaultKeeper? = nil, biometrics: any Biometrics = SystemBiometrics(),
        moment: @escaping @Sendable () -> LockMoment = LockMoment.now,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.vault = vault
        self.biometrics = biometrics
        self.moment = moment
        self.clock = clock
    }

    public var biometricName: String? { biometrics.name }

    public var phoneHasPasscode: Bool { biometrics.passcodeIsSet() }

    public var sealsWhatThisPhoneKeeps: Bool { vault?.vault.isInUse ?? false }

    public var phoneHasChecked: Bool { passed != nil }

    private func lockNow() {
        isLocked = true
        vault?.shut()
        dropCheck()
    }

    public var isCovered: Bool { isLocked || (isAway && (lock != nil || coversWhenAway)) }

    public var offersBiometrics: Bool {
        guard let lock, lock.usesBiometrics, biometrics.name != nil else { return false }
        return lock.allowsBiometrics(currentState: biometrics.state())
    }

    public var biometricsChanged: Bool {
        guard let lock, lock.usesBiometrics, biometrics.name != nil, let state = biometrics.state() else { return false }
        return !lock.allowsBiometrics(currentState: state)
    }

    public func load() async {
        do {
            lock = try await store.load()
            if let vault, try await vault.shutIfThereIsOne(), lock == nil { try await vault.destroy() }
            unreadable = false
            isLocked = lock != nil
        } catch {
            unreadable = true
            isLocked = true
        }
        loaded = true
        askIfDue()
    }

    public func sceneChanged(to phase: ScenePhase) {
        isAway = phase != .active
        isActive = phase == .active
        guard let lock else {
            if unreadable, phase == .active { Task { await load() } }
            return
        }
        switch phase {
        case .active:
            if let leftAt {
                let away = moment().seconds(since: leftAt) ?? .infinity
                if away >= lock.delay { lockNow() }
            }
            self.leftAt = nil
            askIfDue()
        case .background:
            if leftAt == nil, !isLocked { leftAt = moment() }
            guard sheetsUp == 0 else {
                leftWhileASheetWasUp = true
                break
            }
            dropCheck()
            asksWhenActive = true
        default:
            break
        }
    }

    private func sheetEnded() {
        sheetsUp -= 1
        guard sheetsUp == 0, leftWhileASheetWasUp else { return }
        leftWhileASheetWasUp = false
        dropCheck()
        asksWhenActive = true
        askIfDue()
    }

    private func askIfDue() {
        guard isActive, asksWhenActive, loaded, isLocked, let lock, let vault, sealsWhatThisPhoneKeeps else { return }
        asksWhenActive = false
        let wait = lock.remainingWait(at: moment())
        guard wait == 0 else {
            problem = .waitUntil(clock().addingTimeInterval(wait))
            return
        }
        guard biometrics.passcodeIsSet() else {
            problem = .noPasscode
            return
        }
        if problem == .noPasscode { problem = nil }
        if offersBiometrics {
            Task { await unlockWithBiometrics() }
        } else {
            _ = beginAsking(vault, reason: Self.reason(.unlocking))
        }
    }

    private func passedCheck(reason: String) async -> PassedCheck? {
        guard let vault else { return nil }
        if let passed, let passedAt, let since = moment().seconds(since: passedAt), since < Self.checkLasts {
            return passed
        }
        passed = nil
        guard biometrics.passcodeIsSet() else {
            problem = .noPasscode
            return nil
        }
        return await beginAsking(vault, reason: reason).value
    }

    private func beginAsking(_ vault: VaultKeeper, reason: String) -> Task<PassedCheck?, Never> {
        if let asking { return asking }
        let generation = checksAsked
        sheetsUp += 1
        let task = Task { await ask(vault, reason: reason, generation: generation) }
        asking = task
        return task
    }

    private func ask(_ vault: VaultKeeper, reason: String, generation: Int) async -> PassedCheck? {
        let result: Result<PassedCheck, any Error>
        do {
            result = .success(try await vault.askThePhone(reason: reason))
        } catch {
            result = .failure(error)
        }
        asking = nil
        sheetEnded()
        guard generation == checksAsked else { return nil }
        switch result {
        case .success(let check):
            passed = check
            passedAt = moment()
            if problem?.isAboutThePhone == true { problem = nil }
            return check
        case .failure(let error):
            problem = Self.problem(after: error, otherwise: .phoneCouldNotCheck)
            return nil
        }
    }

    private func dropCheck() {
        passed = nil
        passedAt = nil
        checksAsked += 1
    }

    public func unlock(with code: String) async {
        guard await check(code, reason: Self.reason(.unlocking)) else { return }
        isLocked = false
    }

    public func confirm(_ code: String) async -> Bool {
        let right = await check(code, reason: Self.reason(.changing))
        if right { confirmedAt = moment() }
        return right
    }

    public var recentlyConfirmed: Bool {
        guard let confirmedAt, let since = moment().seconds(since: confirmedAt) else { return false }
        return since < Self.confirmationLasts
    }

    private func check(_ code: String, reason: String) async -> Bool {
        guard var lock, !checking else { return false }
        checking = true
        defer { checking = false }

        if let wait = lock.wait(at: moment()) {
            self.lock = lock
            try? await store.save(lock)
            problem = .waitUntil(clock().addingTimeInterval(wait))
            return false
        }
        var check: PassedCheck?
        if vault != nil, sealsWhatThisPhoneKeeps {
            guard let passed = await passedCheck(reason: reason), let current = self.lock else { return false }
            check = passed
            lock = current
        }
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

        let right: Bool
        if let vault, let check {
            do {
                right = try await vault.open(with: code, after: check)
            } catch {
                dropCheck()
                problem = .phoneCouldNotCheck
                return false
            }
        } else {
            let snapshot = lock
            right = await Task.detached(priority: .userInitiated) { snapshot.matches(code) }.value
        }
        guard right else {
            if lock.codesLeftBeforeErasing == 0 {
                problem = .erasing
                erasing = true
                await onEraseEverywhere?()
                return false
            }
            switch lock.afterAWrongCode {
            case .wrong(let left):
                problem = lock.codesLeftBeforeErasing.map { .wrongBeforeErasing($0) } ?? .wrong(triesBeforeAWait: left)
            case .wait(let wait):
                dropCheck()
                problem = .waitUntil(clock().addingTimeInterval(wait))
            case .unlocked: problem = nil
            }
            return false
        }
        dropCheck()
        let facesWentAway = biometricsChanged ? await dropFaceIDAlone() : false
        if var current = self.lock {
            current.succeeded()
            if facesWentAway {
                current.usesBiometrics = false
                current.biometricState = nil
            }
            self.lock = current
            try? await store.save(current)
        }
        problem = nil
        return true
    }

    private func dropFaceIDAlone() async -> Bool {
        guard let vault, sealsWhatThisPhoneKeeps else { return true }
        return (try? await vault.setBiometrics(false)) != nil
    }

    public func unlockWithBiometrics() async {
        guard offersBiometrics else { return }
        let reason = Self.reason(.faces)
        if let vault, sealsWhatThisPhoneKeeps {
            let generation = checksAsked
            sheetsUp += 1
            let opened = (try? await vault.openWithBiometrics(reason: reason)) == true
            sheetEnded()
            guard generation == checksAsked else {
                if isLocked { vault.shut() }
                return
            }
            guard opened else { return }
        } else {
            guard await biometrics.evaluate(reason: reason) else { return }
        }
        guard var lock, lock.allowsBiometrics(currentState: biometrics.state()) else { return }
        dropCheck()
        lock.noteBiometricUnlock()
        self.lock = lock
        try? await store.save(lock)
        problem = nil
        isLocked = false
    }

    private enum Reason { case unlocking, turningOn, changing, faces }

    private static func reason(_ reason: Reason) -> String {
        switch reason {
        // COPY BEGIN d35bb503 [NEEDS HUMAN REVIEW]
        case .faces: String(localized: "Unlock the app", bundle: .module)
        // COPY END d35bb503
        // COPY BEGIN 5e548c33 [NEEDS HUMAN REVIEW]
        case .unlocking: String(localized: "Needed before your code is tried", bundle: .module)
        case .turningOn: String(localized: "Turn on the lock", bundle: .module)
        case .changing: String(localized: "Change the lock", bundle: .module)
        // COPY END 5e548c33
        }
    }

    private static func problem(after error: any Error, otherwise: AppLockProblem) -> AppLockProblem {
        switch error as? HardwareKeyError {
        case .refused: .phoneDidNotCheck
        case .noPasscode: .noPasscode
        case .noSuchKey: .codeIsGone
        default: otherwise
        }
    }

    @discardableResult
    public func turnOn(_ new: AppLock, code: String? = nil) async -> Bool {
        guard lock == nil else { return await replace(with: new, code: code) }
        return await keep(new, code: code)
    }

    public func lockTheApp(with new: AppLock, code: String) async -> AppLockProblem? {
        await turnOn(new, code: code) ? nil : problem ?? .notSaved
    }

    @discardableResult
    public func replace(with new: AppLock, code: String? = nil) async -> Bool {
        guard let current = lock else { return await keep(new, code: code) }
        guard spendConfirmation() else { return false }
        var new = new
        new.usesBiometrics = current.usesBiometrics
        new.biometricState = current.biometricState
        new.delay = current.delay
        new.eraseAfter = current.eraseAfter
        return await keep(new, code: code)
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

    private func keep(_ new: AppLock?, code: String? = nil) async -> Bool {
        var new = new
        if new?.usesBiometrics == true { new?.noteBiometrics(biometrics.state()) }
        var made: SymmetricKey?
        if let vault {
            if new != nil, !vault.vault.isInUse, !biometrics.passcodeIsSet() {
                problem = .noPasscode
                return false
            }
            do {
                made = try await settleVault(vault, for: new, code: code)
            } catch {
                problem = Self.problem(after: error, otherwise: .notSaved)
                return false
            }
            dropCheck()
            if vault.vault.isInUse || made != nil { new = new?.withoutAVerifier }
        }
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
            try? await vault?.destroy()
        }
        if let made, let vault {
            vault.vault.open(with: made)
            _ = await onKeptChanged?()
        }
        return true
    }

    private func settleVault(_ vault: VaultKeeper, for new: AppLock?, code: String?) async throws -> SymmetricKey? {
        guard let new else {
            guard vault.vault.isInUse else { return nil }
            try vault.vault.writeInTheClear()
            guard await onKeptChanged?() ?? true else { throw VaultError.shut }
            return nil
        }
        guard vault.vault.isInUse else {
            guard let code else { return nil }
            sheetsUp += 1
            defer { sheetEnded() }
            return try await vault.make(
                code: code, usingBiometrics: new.usesBiometrics, recovery: vaultRecoverySecret?(),
                reason: Self.reason(.turningOn))
        }
        if let code { try await vault.changeCode(to: code) }
        try await vault.setBiometrics(new.usesBiometrics)
        return nil
    }

    @discardableResult
    public func setEraseAfter(_ count: Int?) async -> Bool {
        guard var lock, spendConfirmation() else { return false }
        lock.eraseAfter = count
        return await keep(lock)
    }

    @discardableResult
    public func unlock(withRecoveryKey text: String) async -> Bool {
        guard lock != nil else {
            problem = .notTheRecoveryKey
            return false
        }
        if let vault, sealsWhatThisPhoneKeeps {
            let secret = (try? RecoveryKey.secret(from: text))?.identity.vaultRecoverySecret
            guard let secret, (try? await vault.openWithRecovery(secret)) == true else {
                problem = .notTheRecoveryKey
                return false
            }
            guard await onReopened?() ?? true else {
                problem = .notSaved
                return false
            }
        } else {
            guard let recovery, recovery.opens(text) else {
                problem = .notTheRecoveryKey
                return false
            }
        }
        return await keep(nil)  // reentrancy considered
    }

    public func forget() {
        Task { [vault] in try? await vault?.destroy() }
        unreadable = false
        lock = nil
        isLocked = false
        problem = nil
        leftAt = nil
        confirmedAt = nil
        dropCheck()
    }
}

public enum AppLockProblem: Hashable, Sendable {
    case wrong(triesBeforeAWait: Int)
    case waitUntil(Date)
    case notSaved
    case needsCode
    case wrongBeforeErasing(Int)
    case erasing
    case notTheRecoveryKey
    case phoneDidNotCheck
    case noPasscode
    case phoneCouldNotCheck
    case codeIsGone

    public var isAboutThePhone: Bool {
        switch self {
        case .phoneDidNotCheck, .noPasscode, .phoneCouldNotCheck, .codeIsGone: true
        default: false
        }
    }
}

public struct NotificationPrivacy {
    public var reveals: @MainActor () -> Bool
    public var makePrivate: @MainActor () async -> Void

    public init(reveals: @escaping @MainActor () -> Bool, makePrivate: @escaping @MainActor () async -> Void) {
        self.reveals = reveals
        self.makePrivate = makePrivate
    }
}

public struct RecoveryKeyAccess {
    public var isSaved: @MainActor () -> Bool
    public var unsaved: @MainActor () -> (text: String, fingerprint: String)?
    public var markSaved: @MainActor () async -> Void
    public var opens: @MainActor (String) -> Bool

    public init(
        isSaved: @escaping @MainActor () -> Bool,
        unsaved: @escaping @MainActor () -> (text: String, fingerprint: String)?,
        markSaved: @escaping @MainActor () async -> Void,
        opens: @escaping @MainActor (String) -> Bool
    ) {
        self.isSaved = isSaved
        self.unsaved = unsaved
        self.markSaved = markSaved
        self.opens = opens
    }
}

extension EnvironmentValues {
    @Entry public var appLock: AppLockController?
}
