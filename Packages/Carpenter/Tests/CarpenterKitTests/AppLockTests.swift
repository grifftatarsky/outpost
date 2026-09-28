import CarpenterKitTesting
import CarpenterUI
import Foundation
import SwiftUI
import Testing

@testable import CarpenterKit

@Suite("Locking the app with a code of its own")
struct AppLockTests {
    private let boot = "boot-one"

    private func at(_ uptime: TimeInterval, boot: String? = nil) -> LockMoment {
        LockMoment(boot: boot ?? self.boot, uptime: uptime)
    }

    private func lock(_ code: String = "482913", as kind: AppLock.Code = .digits, biometrics: Bool = false)
        throws -> AppLock
    {
        try AppLock.make(code, as: kind, usesBiometrics: biometrics, biometricState: biometrics ? Data([1]) : nil, rounds: 1_000)
    }

    @Test("A digit code remembers how many digits it has, so the keypad knows when to try it")
    func aDigitCodeKnowsItsLength() throws {
        #expect(try lock("4829").length == 4)
        #expect(try lock("482913").length == 6)
        #expect(try lock("correct horse", as: .passphrase).length == nil)

        var older = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try lock())) as! [String: Any]
        older.removeValue(forKey: "length")
        let decoded = try JSONDecoder().decode(AppLock.self, from: JSONSerialization.data(withJSONObject: older))
        #expect(decoded.length == nil, "a lock saved before the length was kept should still open, with no length")
        var opened = decoded
        #expect(opened.unlock(with: "482913", at: at(100)) == .unlocked)
    }

    @Test("The right code opens it; a wrong one does not, and says how many tries are left")
    func theRightCodeOpens() throws {
        var lock = try lock()
        #expect(lock.unlock(with: "482914", at: at(100)) == .wrong(triesBeforeAWait: 4))
        #expect(lock.unlock(with: "", at: at(101)) == .wrong(triesBeforeAWait: 3))
        #expect(lock.unlock(with: "482913", at: at(102)) == .unlocked)
        #expect(lock.failures == 0, "a right code left the wrong ones counted")
    }

    @Test("Codes are four to six digits, and a passphrase is at least eight characters")
    func whatACodeMayBe() {
        for good in ["1234", "12345", "123456"] { #expect(AppLock.isAcceptable(good, as: .digits)) }
        for bad in ["123", "1234567", "12a4", "１２３４", "12 34", ""] {
            #expect(!AppLock.isAcceptable(bad, as: .digits), "\(bad) was taken as a code")
        }
        #expect(AppLock.isAcceptable("tangerine sky", as: .passphrase))
        #expect(!AppLock.isAcceptable("short", as: .passphrase))
        #expect(!AppLock.isAcceptable("       x       ", as: .passphrase), "spaces were counted as a passphrase")
        #expect(throws: AppLockError.notAcceptable) { try AppLock.make("12", as: .digits, usesBiometrics: false) }
    }

    @Test("After five wrong codes it makes you wait, longer each time, and even the right code waits")
    func wrongCodesWait() throws {
        var lock = try lock()
        for second in 0..<4 { _ = lock.unlock(with: "000000", at: at(Double(second))) }
        #expect(lock.unlock(with: "000000", at: at(10)) == .wait(60))
        #expect(lock.unlock(with: "482913", at: at(40)) == .wait(30), "the right code skipped the wait")
        #expect(lock.unlock(with: "000000", at: at(71)) == .wait(300))
        #expect(lock.unlock(with: "000000", at: at(400)) == .wait(900))
        #expect(lock.unlock(with: "000000", at: at(1_400)) == .wait(3_600))
        #expect(lock.unlock(with: "482913", at: at(1_400 + 3_600)) == .unlocked)
    }

    @Test("A wait is kept by the phone's own running time, so setting its clock does not end it")
    func theClockCannotSkipAWait() throws {
        var lock = try lock()
        for second in 0..<5 { _ = lock.unlock(with: "000000", at: at(Double(second))) }
        #expect(lock.unlock(with: "482913", at: at(30)) != .unlocked)
        #expect(lock.remainingWait(at: at(30)) > 0)
        let json = String(decoding: try JSONEncoder().encode(lock), as: UTF8.self)
        #expect(!json.contains("waitUntil"), "the wait is still kept as a date on the clock the phone's owner sets")
    }

    @Test("Restarting the phone starts a wait again rather than ending it")
    func aRestartDoesNotEndAWait() throws {
        var lock = try lock()
        for second in 0..<5 { _ = lock.unlock(with: "000000", at: at(1_000 + Double(second))) }
        #expect(lock.unlock(with: "482913", at: at(5, boot: "boot-two")) == .wait(60), "a restart ended the wait")
        #expect(lock.unlock(with: "482913", at: at(30, boot: "boot-two")) == .wait(35))
        #expect(lock.unlock(with: "482913", at: at(66, boot: "boot-two")) == .unlocked)

        var unknown = try self.lock()
        for second in 0..<5 { _ = unknown.unlock(with: "000000", at: LockMoment(boot: nil, uptime: 900 + Double(second))) }
        #expect(
            unknown.unlock(with: "482913", at: LockMoment(boot: nil, uptime: 3)) == .wait(60),
            "running time that went backwards was read as time served")
    }

    @Test("The code itself is not kept, only something it takes the right code to match")
    func theCodeIsNotKept() throws {
        let lock = try lock("tangerine sky", as: .passphrase)
        let encoded = try JSONEncoder().encode(lock)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("tangerine"))
        #expect(lock.verifier != Data("tangerine sky".utf8))
        let other = try self.lock("tangerine sky", as: .passphrase)
        #expect(other.verifier != lock.verifier, "two locks with the same code matched, so there is no salt")
        #expect(lock.matches("tangerine sky"))
        #expect(!lock.matches("tangerine skY"))
    }

    @Test("Face ID counts only while the faces it knows are the ones it knew when the lock was set")
    func aNewFaceNeedsTheCode() throws {
        var lock = try lock(biometrics: true)
        #expect(lock.allowsBiometrics(currentState: Data([1])))
        #expect(!lock.allowsBiometrics(currentState: Data([2])), "a face added since the lock was set could open it")
        #expect(!lock.allowsBiometrics(currentState: nil))
        lock.noteBiometrics(Data([2]))
        #expect(lock.allowsBiometrics(currentState: Data([2])))
        let codeOnly = try self.lock()
        #expect(!codeOnly.allowsBiometrics(currentState: Data([1])))
    }

    @Test("The lock is kept on this device only, and goes when it is removed")
    func keptOnTheDevice() async throws {
        let keychain = InMemoryKeychainStore()
        let store = AppLockStore(keychain: keychain)
        let lock = try lock()
        try await store.save(lock)
        #expect(try await store.load() == lock)
        #expect(await keychain.scope(for: AppLockStore.key) == .device)
        #expect(try await AppLockStore(keychain: await keychain.sibling()).load() == nil)
        try await store.remove()
        #expect(try await store.load() == nil)
    }
}

@MainActor
@Suite("What the lock lets somebody holding the phone do")
struct AppLockControllerTests {
    final class Uptime: @unchecked Sendable {
        var seconds: TimeInterval = 1_000
        var boot = "boot-one"
        var moment: LockMoment { LockMoment(boot: boot, uptime: seconds) }
    }

    struct Faces: Biometrics {
        let enrolled: Data
        let matches: Bool
        var name: String? { "Face ID" }
        func state() -> Data? { enrolled }
        func evaluate(reason: String) async -> Bool { matches }
    }

    final class Recording: KeychainStore, @unchecked Sendable {
        let inner = InMemoryKeychainStore()
        var saved: [AppLock] = []

        func data(for key: KeychainKey) async throws -> Data? { try await inner.data(for: key) }
        func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws {
            if key == AppLockStore.key, let lock = try? JSONDecoder().decode(AppLock.self, from: data) {
                saved.append(lock)
            }
            try await inner.set(data, for: key, scope: scope)
        }
        func remove(_ key: KeychainKey) async throws { try await inner.remove(key) }
        func removeAll() async throws { try await inner.removeAll() }
    }

    private func controller(
        code: String = "482913", biometrics: Bool = false, faces: Faces = Faces(enrolled: Data([1]), matches: true)
    ) async throws -> (AppLockController, Recording, Uptime) {
        let keychain = Recording()
        let store = AppLockStore(keychain: keychain)
        try await store.save(
            try AppLock.make(code, as: .digits, usesBiometrics: biometrics, biometricState: faces.enrolled, rounds: 1_000))
        keychain.saved = []
        let uptime = Uptime()
        let controller = AppLockController(store: store, biometrics: faces, moment: { uptime.moment })
        await controller.load()
        return (controller, keychain, uptime)
    }

    @Test("Every try is written down before it is checked, so quitting mid-check does not reset the count")
    func aTryIsCountedFirst() async throws {
        let (controller, keychain, _) = try await controller()
        await controller.unlock(with: "482913")
        #expect(!controller.isLocked)
        #expect(
            keychain.saved.map(\.failures) == [1, 0],
            "the try was not written down before it was known to be right: \(keychain.saved.map(\.failures))")

        let (wrong, wrongKeychain, _) = try await self.controller()
        await wrong.unlock(with: "111111")
        #expect(wrong.isLocked)
        #expect(wrongKeychain.saved.map(\.failures) == [1])
        let reopened = try #require(try await AppLockStore(keychain: wrongKeychain).load())
        #expect(reopened.failures == 1, "a wrong try was forgotten when the app was opened again")
    }

    @Test("Opening the app again after a wait began does not end the wait")
    func relaunchingKeepsTheWait() async throws {
        let (controller, keychain, uptime) = try await controller()
        for _ in 0..<5 {
            await controller.unlock(with: "000000")
            uptime.seconds += 1
        }
        let again = AppLockController(store: AppLockStore(keychain: keychain), biometrics: Faces(enrolled: Data([1]), matches: false), moment: { uptime.moment })
        await again.load()
        await again.unlock(with: "482913")
        #expect(again.isLocked, "the right code opened it during a wait, after a relaunch")
        guard case .waitUntil = again.problem else {
            Issue.record("no wait was shown: \(String(describing: again.problem))")
            return
        }
        uptime.seconds += 61
        await again.unlock(with: "482913")
        #expect(!again.isLocked)
    }

    @Test("Leaving and coming back inside the grace keeps it open; after it, or after a restart, it locks")
    func graceIsRunningTime() async throws {
        let (controller, _, uptime) = try await controller()
        await controller.unlock(with: "482913")
        _ = await controller.confirm("482913")
        #expect(await controller.setDelay(60))
        controller.sceneChanged(to: .background)
        uptime.seconds += 30
        controller.sceneChanged(to: .active)
        #expect(!controller.isLocked, "it locked inside the grace")

        controller.sceneChanged(to: .background)
        uptime.seconds += 61
        controller.sceneChanged(to: .active)
        #expect(controller.isLocked, "it stayed open past the grace")

        await controller.unlock(with: "482913")
        controller.sceneChanged(to: .background)
        uptime.boot = "boot-two"
        uptime.seconds = 5
        controller.sceneChanged(to: .active)
        #expect(controller.isLocked, "a restart read as coming straight back")
    }

    @Test("Covering starts the moment the app is not in front, whatever the grace")
    func coveredWhileAway() async throws {
        let (controller, _, _) = try await controller()
        await controller.unlock(with: "482913")
        controller.sceneChanged(to: .inactive)
        #expect(controller.isCovered, "the app switcher could see the screen")
        controller.sceneChanged(to: .active)
        #expect(!controller.isCovered)
    }

    @Test("Nothing that weakens the lock happens without the code, entered just before")
    func weakeningNeedsTheCode() async throws {
        let (controller, _, uptime) = try await controller(faces: Faces(enrolled: Data([2]), matches: true))
        await controller.unlock(with: "482913")

        #expect(!(await controller.turnOff()), "the lock was turned off without its code")
        #expect(!(await controller.setBiometrics(true)), "Face ID was turned on without the code")
        #expect(!(await controller.setDelay(900)), "the grace was lengthened without the code")
        #expect(!(await controller.replace(with: try AppLock.make("1111", as: .digits, usesBiometrics: false, rounds: 1_000))))
        #expect(controller.lock?.usesBiometrics == false && controller.lock?.delay == 0)
        #expect(controller.problem == .needsCode)

        #expect(await controller.setDelay(0), "shortening the grace, which only makes it stricter, asked for the code")
        #expect(await controller.setBiometrics(false))

        #expect(!(await controller.confirm("000000")))
        #expect(!(await controller.turnOff()), "a wrong code let the lock be turned off")

        #expect(await controller.confirm("482913"))
        uptime.seconds += AppLockController.confirmationLasts + 1
        #expect(!(await controller.turnOff()), "a code entered long ago still counted")

        #expect(await controller.confirm("482913"))
        #expect(await controller.setBiometrics(true))
        #expect(!(await controller.turnOff()), "one entry of the code allowed two changes")
        #expect(await controller.confirm("482913"))
        #expect(await controller.turnOff())
        #expect(controller.lock == nil)
    }

    @Test("A face added to the phone after the lock was set does not open it")
    func aNewFaceIsRefused() async throws {
        let keychain = Recording()
        let store = AppLockStore(keychain: keychain)
        try await store.save(
            try AppLock.make("482913", as: .digits, usesBiometrics: true, biometricState: Data([1]), rounds: 1_000))
        let changed = AppLockController(
            store: store, biometrics: Faces(enrolled: Data([1, 9]), matches: true), moment: { LockMoment(boot: "b", uptime: 1) })
        await changed.load()
        #expect(!changed.offersBiometrics)
        #expect(changed.biometricsChanged)
        await changed.unlockWithBiometrics()
        #expect(changed.isLocked, "a face enrolled after the lock was set opened it")

        let same = AppLockController(
            store: store, biometrics: Faces(enrolled: Data([1]), matches: true), moment: { LockMoment(boot: "b", uptime: 1) })
        await same.load()
        await same.unlockWithBiometrics()
        #expect(!same.isLocked)
    }

    final class Unreadable: KeychainStore, @unchecked Sendable {
        let inner = InMemoryKeychainStore()
        var readable = false
        struct NotYet: Error {}

        func data(for key: KeychainKey) async throws -> Data? {
            guard readable else { throw NotYet() }
            return try await inner.data(for: key)
        }
        func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws {
            try await inner.set(data, for: key, scope: scope)
        }
        func remove(_ key: KeychainKey) async throws { try await inner.remove(key) }
        func removeAll() async throws { try await inner.removeAll() }
    }

    @Test("A lock that cannot be read yet, before the phone's first unlock, keeps the app covered")
    func anUnreadableLockStaysShut() async throws {
        let keychain = Unreadable()
        let store = AppLockStore(keychain: keychain)
        try await store.save(try AppLock.make("482913", as: .digits, usesBiometrics: false, rounds: 1_000))
        let controller = AppLockController(
            store: store, biometrics: Faces(enrolled: Data([1]), matches: true), moment: { LockMoment(boot: "b", uptime: 1) })
        await controller.load()
        #expect(controller.isLocked && controller.isCovered, "a lock it could not read was taken as no lock")
        controller.sceneChanged(to: .active)
        #expect(controller.isCovered, "coming to the front uncovered a lock nobody had read")

        keychain.readable = true
        await controller.load()
        #expect(controller.lock != nil && controller.isLocked)
        await controller.unlock(with: "482913")
        #expect(!controller.isLocked)

        let none = AppLockController(
            store: AppLockStore(keychain: InMemoryKeychainStore()), biometrics: Faces(enrolled: Data([1]), matches: true))
        await none.load()
        #expect(!none.isLocked && !none.isCovered && none.loaded)
    }

    private func erasing(after count: Int?) async throws -> (AppLockController, Recording, Uptime, Counter) {
        let (controller, keychain, uptime) = try await controller()
        let erased = Counter()
        controller.onEraseEverywhere = { erased.count += 1 }
        if let count {
            await controller.unlock(with: "482913")
            _ = await controller.confirm("482913")
            #expect(await controller.setEraseAfter(count))
            controller.sceneChanged(to: .background)
            uptime.boot = "boot-restart"
            uptime.seconds = 1
            controller.sceneChanged(to: .active)
            try #require(controller.isLocked, "precondition: locked again")
        }
        return (controller, keychain, uptime, erased)
    }

    final class Counter: @unchecked Sendable { var count = 0 }

    @Test("Set to erase after one wrong code, one wrong code erases everything, and a right one never does")
    func oneWrongCodeErases() async throws {
        let (controller, _, _, erased) = try await erasing(after: 1)
        await controller.unlock(with: "482913")
        #expect(erased.count == 0, "the right code erased everything")
        controller.sceneChanged(to: .background)
        controller.sceneChanged(to: .active)
        await controller.unlock(with: "000000")
        #expect(erased.count == 1, "a wrong code did not erase anything")
        #expect(controller.problem == .erasing)
    }

    @Test("Set to five, four wrong codes warn and the fifth erases, even across a relaunch")
    func theCountSurvivesARelaunch() async throws {
        let (controller, keychain, uptime, erased) = try await erasing(after: 5)
        for _ in 0..<2 { await controller.unlock(with: "000000") }
        #expect(controller.problem == .wrongBeforeErasing(3))
        let again = AppLockController(
            store: AppLockStore(keychain: keychain), biometrics: Faces(enrolled: Data([1]), matches: false),
            moment: { uptime.moment })
        again.onEraseEverywhere = { erased.count += 1 }
        await again.load()
        await again.unlock(with: "000000")
        await again.unlock(with: "000000")
        #expect(erased.count == 0, "it erased before the count")
        #expect(again.problem == .wrongBeforeErasing(1))
        await again.unlock(with: "000000")
        #expect(erased.count == 1, "the fifth wrong code did not erase")
    }

    @Test("Off, no number of wrong codes erases anything")
    func offNeverErases() async throws {
        let (controller, _, uptime, erased) = try await erasing(after: nil)
        for _ in 0..<12 {
            await controller.unlock(with: "000000")
            uptime.seconds += 3_700
        }
        #expect(erased.count == 0)
    }

    @Test("Turning erasing on, changing it or turning it off all need the code")
    func erasingNeedsTheCode() async throws {
        let (controller, _, _) = try await controller()
        await controller.unlock(with: "482913")
        #expect(!(await controller.setEraseAfter(1)), "erasing was turned on without the code")
        #expect(await controller.confirm("482913"))
        #expect(await controller.setEraseAfter(10))
        #expect(!(await controller.setEraseAfter(nil)), "erasing was turned off without the code")
        #expect(controller.lock?.eraseAfter == 10)
    }

    @Test("A wrong code typed to confirm a change counts toward erasing too")
    func confirmingCounts() async throws {
        let (controller, _, _, erased) = try await erasing(after: 1)
        await controller.unlock(with: "482913")
        #expect(!(await controller.confirm("111111")))
        #expect(erased.count == 1, "a wrong code in Settings did not count")
    }

    @Test("The recovery key for this identity opens the app and turns the lock off; any other key does not")
    func theRecoveryKeyOpensIt() async throws {
        let (controller, keychain, _) = try await controller()
        let genuine = "the member's key"
        controller.recovery = RecoveryKeyAccess(
            isSaved: { true }, unsaved: { nil }, markSaved: {}, opens: { $0 == genuine })
        #expect(!(await controller.unlock(withRecoveryKey: "somebody else's key")))
        #expect(controller.isLocked && controller.problem == .notTheRecoveryKey)
        #expect(await controller.unlock(withRecoveryKey: genuine))
        #expect(!controller.isLocked && !controller.isCovered && controller.lock == nil)
        #expect(try await AppLockStore(keychain: keychain).load() == nil, "the lock was left in the keychain")
    }

    @Test("Without a way to check a recovery key, none opens the lock")
    func noCheckerNoRecovery() async throws {
        let (controller, _, _) = try await controller()
        #expect(!(await controller.unlock(withRecoveryKey: "anything")))
        #expect(controller.isLocked)
    }

    @Test("A lock saved before erasing existed reads as erasing off")
    func olderLocksReadAsOff() throws {
        let lock = try AppLock.make("482913", as: .digits, usesBiometrics: false, rounds: 1_000)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(lock)) as? [String: Any])
        json.removeValue(forKey: "eraseAfter")
        let decoded = try JSONDecoder().decode(AppLock.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.eraseAfter == nil)
        #expect(decoded.matches("482913"))
    }

    @Test("Forgetting the lock after an erase leaves nothing locked or covered")
    func forgetClears() async throws {
        let (controller, _, _) = try await controller()
        #expect(controller.isLocked && controller.isCovered)
        controller.forget()
        #expect(!controller.isLocked && !controller.isCovered && controller.lock == nil)
    }
}
