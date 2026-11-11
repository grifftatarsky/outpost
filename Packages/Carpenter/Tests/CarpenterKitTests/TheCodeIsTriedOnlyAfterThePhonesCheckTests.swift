@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
@testable import CarpenterUI
import Foundation
import SwiftUI
import Testing

@MainActor
@Suite("With the lock on, a code is tried only after the phone has checked Face ID or its passcode", .serialized, .tags(.crypto))
struct TheCodeIsTriedOnlyAfterThePhonesCheckTests {
    private final class Uptime: @unchecked Sendable {
        var seconds: TimeInterval = 1_000
        var moment: LockMoment { LockMoment(boot: "boot-one", uptime: seconds) }
    }

    private final class Faces: Biometrics, @unchecked Sendable {
        var enrolled: Data? = Data([1])
        var passcode = true
        var name: String? { "Face ID" }
        func state() -> Data? { enrolled }
        func passcodeIsSet() -> Bool { passcode }
        func evaluate(reason: String) async -> Bool { false }
    }

    private struct Phone {
        let directory = TestScratch.root.appending(path: "phone-check-\(UUID().uuidString)")
        let keychain = InMemoryKeychainStore()
        let hardware = FakeHardwareKeys()
        let uptime = Uptime()
        let faces = Faces()

        func changeFaces() async {
            faces.enrolled = Data([2])
            await hardware.changeFaces()
        }

        func turnOffPasscode(keysSurvive: Bool) async {
            faces.passcode = false
            await hardware.turnOffPasscode(keysSurvive: keysSurvive)
        }

        func turnOnPasscode() async {
            faces.passcode = true
            await hardware.turnOnPasscode()
        }
    }

    @MainActor
    private final class Launch {
        let phone: Phone
        let vault = OpenVault()
        let session: AppSession
        let controller: AppLockController
        let keeper: VaultKeeper
        var erased = false

        init(_ phone: Phone) {
            self.phone = phone
            let keeper = VaultKeeper(keychain: phone.keychain, hardware: phone.hardware, vault: vault, rounds: 1_000)
            let session = AppSession(
                storage: TestSession.storage(keychain: phone.keychain, at: phone.directory).sealed(by: vault),
                clock: TestClock(now: TestSession.now), denyList: .empty)
            let uptime = phone.uptime
            let controller = AppLockController(
                store: AppLockStore(keychain: phone.keychain), vault: keeper, biometrics: phone.faces,
                moment: { uptime.moment })
            controller.onKeptChanged = { (try? await session.rewriteWhatThisPhoneKeeps()) != nil }
            controller.vaultRecoverySecret = { session.enrolment?.identity.vaultRecoverySecret }
            controller.onReopened = {
                await session.load()
                return session.enrolment != nil
            }
            self.keeper = keeper
            self.session = session
            self.controller = controller
            controller.onEraseEverywhere = { [weak self] in self?.erased = true }
        }

        func open() async {
            _ = try? await keeper.shutIfThereIsOne()
            await controller.load()
            await session.load()
        }

        func identityIsSealed() async throws -> Bool {
            SealedKeychainStore.isSealed(try #require(try await phone.keychain.data(for: IdentityStore.identityKey)))
        }

        func leaveAndComeBack(after seconds: TimeInterval = 3_600) {
            controller.sceneChanged(to: .inactive)
            controller.sceneChanged(to: .background)
            phone.uptime.seconds += seconds
            controller.sceneChanged(to: .inactive)
            controller.sceneChanged(to: .active)
        }
    }

    private static let code = "482913"

    private func lock(_ code: String = code, biometrics: Bool = false) throws -> AppLock {
        try AppLock.make(code, as: .digits, usesBiometrics: biometrics, biometricState: Data([1]), rounds: 1_000)
    }

    private func newPhone() async throws -> (Phone, Launch, String) {
        let phone = Phone()
        let first = Launch(phone)
        await first.open()
        try await first.session.createIdentity(displayName: "Alice")
        _ = try await first.session.createRoom(named: "Lanterns")
        return (phone, first, try #require(first.session.recoveryKeyText()))
    }

    private func phoneWithTheLockOn(biometrics: Bool = false) async throws -> (Phone, String) {
        let (phone, first, text) = try await newPhone()
        #expect(await first.controller.turnOn(try lock(biometrics: biometrics), code: Self.code))
        #expect(try await first.identityIsSealed(), "turning the lock on left the identity in the clear")
        return (phone, text)
    }

    private func relaunch(_ phone: Phone) async -> Launch {
        let launch = Launch(phone)
        await launch.open()
        return launch
    }

    private func until(_ condition: () async -> Bool) async {
        for _ in 0..<2_000 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test("Until the phone's check passes, the right code opens nothing and no code is tested")
    func noCheckNoGuess() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let launch = await relaunch(phone)
        let before = await phone.hardware.agreements

        await phone.hardware.hand(to: .somebodyWhoCancels)
        await launch.controller.unlock(with: Self.code)

        #expect(launch.controller.isLocked)
        #expect(launch.vault.isShut)
        #expect(await phone.hardware.agreements == before, "the enclave gave out what a code is tested against")
        #expect(launch.controller.problem == .phoneDidNotCheck)
    }

    @Test("Somebody with the phone's files and a phone that refuses cannot tell a right code from a wrong one")
    func aRefusingPhoneGivesNothingToGuessAgainst() async throws {
        let hardware = FakeHardwareKeys()
        let (_, sealed) = try await Vault.create(code: "1234", usingBiometrics: true, hardware: hardware, rounds: 1_000)
        await hardware.hand(to: .somebodyWhoFails)

        await #expect(throws: HardwareKeyError.refused) {
            _ = try await Vault.askThePhone(sealed, hardware: hardware, reason: "Needed before your code is tried")
        }
        await #expect(throws: HardwareKeyError.refused) {
            _ = try await Vault.openWithBiometrics(sealed, hardware: hardware, reason: "Unlock the app")
        }
        #expect(await hardware.agreements == 0)

        let elsewhere = FakeHardwareKeys()
        _ = try await elsewhere.make(sealed.byCode.hardware, opensFor: .ownerPresent)
        let theirs = try await Vault.askThePhone(sealed, hardware: elsewhere, reason: "Needed before your code is tried")
        for guess in ["1234", "0000", "4321"] {
            #expect(throws: VaultError.wrongCode) { _ = try Vault.open(sealed, with: guess, after: theirs) }
        }
    }

    @Test("The code's key is made to ask for the owner, the recovery key's for an unlocked phone, and Face ID's for the enrolled faces")
    func eachKeyHasItsRule() async throws {
        let hardware = FakeHardwareKeys()
        let (_, sealed) = try await Vault.create(
            code: "824193", usingBiometrics: true, recovery: Data(repeating: 7, count: 32), hardware: hardware,
            rounds: 1_000)
        #expect(await hardware.rule(of: sealed.byCode.hardware) == .ownerPresent)
        #expect(await hardware.rule(of: try #require(sealed.byBiometrics).hardware) == .enrolledFaces)
        #expect(await hardware.rule(of: try #require(sealed.byRecovery).hardware) == .unlockedPhone)
        #expect(await hardware.sheets == 0, "making the wrappings asked the phone")
    }

    @Test("A cancelled check counts no try and starts no wait")
    func aCancelledCheckCountsNothing() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let launch = await relaunch(phone)
        await phone.hardware.hand(to: .somebodyWhoCancels)

        for _ in 0..<10 { await launch.controller.unlock(with: "000000") }

        #expect(launch.controller.lock?.failures == 0)
        #expect(try await AppLockStore(keychain: phone.keychain).load()?.failures == 0)
        #expect(launch.controller.problem == .phoneDidNotCheck)
        await phone.hardware.hand(to: .owner)
        await launch.controller.unlock(with: Self.code)
        #expect(!launch.controller.isLocked, "ten refused checks left a wait behind")
    }

    @Test("With Erase after 1, a cancelled check and a failed check erase nothing")
    func aRefusedCheckNeverErases() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let setUp = await relaunch(phone)
        await setUp.controller.unlock(with: Self.code)
        #expect(await setUp.controller.confirm(Self.code))
        #expect(await setUp.controller.setEraseAfter(1))

        let launch = await relaunch(phone)
        await phone.hardware.hand(to: .somebodyWhoCancels)
        await launch.controller.unlock(with: "000000")
        await phone.hardware.hand(to: .somebodyWhoFails)
        await launch.controller.unlock(with: "000000")

        #expect(!launch.erased)
        #expect(!launch.controller.erasing)
        #expect(launch.controller.lock?.codesLeftBeforeErasing == 1)
    }

    @Test("A wrong code after a passed check counts, and the next try raises no second sheet")
    func oneSheetForAWrongThenARightCode() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let launch = await relaunch(phone)
        let before = await phone.hardware.sheets

        await launch.controller.unlock(with: "000000")
        #expect(launch.controller.lock?.failures == 1)
        await launch.controller.unlock(with: Self.code)

        #expect(!launch.controller.isLocked)
        #expect(await phone.hardware.sheets == before + 1)
    }

    @Test("A code typed while the sheet is still up waits for that sheet")
    func aCodeWaitsForTheSheetAlreadyUp() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let launch = await relaunch(phone)
        let before = await phone.hardware.sheets
        await phone.hardware.holdSheetsOpen()

        launch.controller.sceneChanged(to: .active)
        await until { await phone.hardware.sheetsWaiting == 1 }
        let typed = Task { await launch.controller.unlock(with: Self.code) }
        await phone.hardware.answerHeldSheets()
        await typed.value

        #expect(!launch.controller.isLocked)
        #expect(await phone.hardware.sheets == before + 1)
    }

    @Test("During a wait no sheet is raised, by a code or by coming back to the app")
    func noSheetDuringAWait() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let launch = await relaunch(phone)
        for _ in 0..<5 { await launch.controller.unlock(with: "000000") }
        guard case .waitUntil = launch.controller.problem else {
            Issue.record("five wrong codes started no wait")
            return
        }
        let sheets = await phone.hardware.sheets

        await launch.controller.unlock(with: Self.code)
        launch.leaveAndComeBack(after: 10)
        await launch.controller.unlock(with: Self.code)

        #expect(await phone.hardware.sheets == sheets)
        #expect(launch.controller.isLocked)
        guard case .waitUntil = launch.controller.problem else {
            Issue.record("the wait was not said: \(String(describing: launch.controller.problem))")
            return
        }
    }

    @Test("The phone's passcode passes the check and opens nothing by itself")
    func thePasscodeAloneOpensNothing() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let launch = await relaunch(phone)
        await phone.hardware.hand(to: .ownerWithThePasscode)

        launch.controller.sceneChanged(to: .active)
        await until { launch.controller.phoneHasChecked }

        #expect(launch.controller.phoneHasChecked)
        #expect(launch.controller.isLocked)
        #expect(launch.vault.isShut)
        await launch.controller.unlock(with: "000000")
        #expect(launch.controller.isLocked)
        await launch.controller.unlock(with: Self.code)
        #expect(!launch.controller.isLocked)
    }

    @Test("A sheet answered with the phone's passcode does not open Face ID alone")
    func thePasscodeDoesNotOpenFaceIDAlone() async throws {
        let (phone, _) = try await phoneWithTheLockOn(biometrics: true)
        let launch = await relaunch(phone)
        await phone.hardware.hand(to: .ownerWithThePasscode)

        await launch.controller.unlockWithBiometrics()

        #expect(launch.controller.isLocked)
        #expect(launch.vault.isShut)
    }

    @Test("Turning the lock on raises one sheet, with Face ID alone and without")
    func turningItOnRaisesOneSheet() async throws {
        for biometrics in [false, true] {
            let (phone, first, _) = try await newPhone()
            #expect(await first.controller.turnOn(try lock(biometrics: biometrics), code: Self.code))
            #expect(await phone.hardware.sheets == 1, "with Face ID alone \(biometrics ? "on" : "off")")
        }
    }

    @Test("If the check is refused while turning the lock on, nothing is sealed, no vault or hardware key is kept and no lock is saved")
    func aRefusedCheckTurnsNothingOn() async throws {
        for holder in [FakeHardwareKeys.Holder.somebodyWhoCancels, .somebodyWhoFails] {
            let (phone, first, _) = try await newPhone()
            await phone.hardware.hand(to: holder)

            #expect(await first.controller.turnOn(try lock(biometrics: true), code: Self.code) == false)

            #expect(first.controller.problem == .phoneDidNotCheck)
            #expect(first.controller.lock == nil)
            #expect(try await first.keeper.sealed() == nil)
            #expect(await phone.hardware.held.isEmpty, "a hardware key was left behind")
            #expect(try await AppLockStore(keychain: phone.keychain).load() == nil)
            #expect(try await first.identityIsSealed() == false)
            #expect(!first.vault.isInUse)
        }
    }

    @Test("A phone with no passcode cannot turn the lock on, and nothing is sealed")
    func noPasscodeNoLock() async throws {
        for makingNeedsAPasscode in [false, true] {
            let (phone, first, _) = try await newPhone()
            await phone.turnOffPasscode(keysSurvive: true)
            await phone.hardware.setMakingNeedsAPasscode(makingNeedsAPasscode)

            #expect(await first.controller.turnOn(try lock(), code: Self.code) == false)

            #expect(first.controller.problem == .noPasscode)
            #expect(try await first.keeper.sealed() == nil)
            #expect(await phone.hardware.held.isEmpty)
            #expect(try await first.identityIsSealed() == false)
        }
    }

    @Test("Even when the question says there is a passcode, a phone without one turns nothing on")
    func theEnclaveHasTheLastWordOnThePasscode() async throws {
        let (phone, first, _) = try await newPhone()
        await phone.hardware.turnOffPasscode(keysSurvive: true)

        #expect(await first.controller.turnOn(try lock(), code: Self.code) == false)

        #expect(first.controller.problem == .noPasscode)
        #expect(try await first.keeper.sealed() == nil)
        #expect(await phone.hardware.held.isEmpty)
    }

    @Test("The recovery key opens with no sheet, and with no passcode on the phone")
    func theRecoveryKeyNeedsNoCheck() async throws {
        let (phone, text) = try await phoneWithTheLockOn()
        await phone.turnOffPasscode(keysSurvive: true)
        let launch = await relaunch(phone)
        let sheets = await phone.hardware.sheets

        #expect(await launch.controller.unlock(withRecoveryKey: text))

        #expect(await phone.hardware.sheets == sheets)
        #expect(!launch.controller.isLocked)
        #expect(launch.session.enrolment != nil)
    }

    @Test("With the passcode turned off after the lock is on, a code counts nothing and the recovery key opens")
    func noPasscodeAfterwards() async throws {
        for keysSurvive in [true, false] {
            let (phone, text) = try await phoneWithTheLockOn()
            await phone.turnOffPasscode(keysSurvive: keysSurvive)
            let launch = await relaunch(phone)

            launch.controller.sceneChanged(to: .active)
            #expect(launch.controller.problem == .noPasscode)
            await launch.controller.unlock(with: Self.code)

            #expect(launch.controller.isLocked)
            #expect(launch.controller.lock?.failures == 0)
            #expect(launch.controller.problem == .noPasscode)
            #expect(await launch.controller.unlock(withRecoveryKey: text), "keys \(keysSurvive ? "kept" : "gone")")
            #expect(launch.session.enrolment != nil)
        }
    }

    @Test("With the passcode turned off and on again and the code's key gone, the lock screen says the code is finished here, counts nothing, and the recovery key opens")
    func theCodesKeyIsGone() async throws {
        let (phone, text) = try await phoneWithTheLockOn()
        await phone.turnOffPasscode(keysSurvive: false)
        await phone.turnOnPasscode()
        let launch = await relaunch(phone)

        launch.controller.sceneChanged(to: .active)
        await until { launch.controller.problem == .codeIsGone }
        #expect(launch.controller.problem == .codeIsGone)
        await launch.controller.unlock(with: Self.code)

        #expect(launch.controller.isLocked)
        #expect(launch.controller.lock?.failures == 0)
        #expect(launch.controller.problem == .codeIsGone)
        #expect(await launch.controller.unlock(withRecoveryKey: text))
        #expect(launch.session.enrolment != nil)
    }

    @Test("Leaving the app while a sheet from Settings is up still starts the away clock, so the app is locked when it comes back")
    func leavingWithASheetUpStillLocks() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let launch = await relaunch(phone)
        await launch.controller.unlock(with: Self.code)
        #expect(!launch.controller.isLocked)
        launch.controller.sceneChanged(to: .active)
        await phone.hardware.holdSheetsOpen()

        let confirming = Task { await launch.controller.confirm(Self.code) }
        await until { await phone.hardware.sheetsWaiting == 1 }
        launch.controller.sceneChanged(to: .inactive)
        launch.controller.sceneChanged(to: .background)
        phone.uptime.seconds += 3_600
        await phone.hardware.answerHeldSheets()
        #expect(!(await confirming.value), "a sheet answered while the app was away let a code count")
        launch.controller.sceneChanged(to: .inactive)
        launch.controller.sceneChanged(to: .active)

        #expect(launch.controller.isLocked, "the app came back unlocked after an hour away")
    }

    @Test("Leaving the lock screen while its sheet is up and coming back raises the sheet again")
    func leavingTheLockScreenWithItsSheetUpAsksAgain() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let launch = await relaunch(phone)
        let before = await phone.hardware.sheets
        await phone.hardware.holdSheetsOpen()
        await phone.hardware.hand(to: .somebodyWhoCancels)

        launch.controller.sceneChanged(to: .active)
        await until { await phone.hardware.sheetsWaiting == 1 }
        launch.controller.sceneChanged(to: .inactive)
        launch.controller.sceneChanged(to: .background)
        await phone.hardware.answerHeldSheets()
        try await Task.sleep(for: .milliseconds(20))
        await phone.hardware.hand(to: .owner)
        launch.controller.sceneChanged(to: .inactive)
        launch.controller.sceneChanged(to: .active)
        await until { launch.controller.phoneHasChecked }

        #expect(await phone.hardware.sheets == before + 2)
        #expect(launch.controller.phoneHasChecked)
    }

    @Test("Started in the background, the app asks the phone when it first becomes active, before any code")
    func startedInTheBackground() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let before = await phone.hardware.sheets
        let launch = await relaunch(phone)
        launch.controller.sceneChanged(to: .background)
        #expect(await phone.hardware.sheets == before, "a sheet was asked for while the app was in the background")

        launch.controller.sceneChanged(to: .inactive)
        launch.controller.sceneChanged(to: .active)
        await until { launch.controller.phoneHasChecked }

        #expect(await phone.hardware.sheets == before + 1)
        await launch.controller.unlock(with: Self.code)
        #expect(!launch.controller.isLocked)
        #expect(await phone.hardware.sheets == before + 1)
    }

    @Test("Leaving the lock screen and coming back drops the passed check and asks again")
    func leavingTheLockScreenAsksAgain() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let launch = await relaunch(phone)
        let before = await phone.hardware.sheets
        launch.controller.sceneChanged(to: .active)
        await until { launch.controller.phoneHasChecked }

        launch.controller.sceneChanged(to: .inactive)
        launch.controller.sceneChanged(to: .background)
        #expect(!launch.controller.phoneHasChecked)
        launch.controller.sceneChanged(to: .inactive)
        launch.controller.sceneChanged(to: .active)
        await until { launch.controller.phoneHasChecked }

        #expect(await phone.hardware.sheets == before + 2)
    }

    @Test("A cancelled sheet is not raised again until a code is entered or the app comes back")
    func aCancelledSheetStaysDown() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let launch = await relaunch(phone)
        let before = await phone.hardware.sheets
        await phone.hardware.hand(to: .somebodyWhoCancels)

        launch.controller.sceneChanged(to: .active)
        await until { launch.controller.problem == .phoneDidNotCheck }
        launch.controller.sceneChanged(to: .inactive)
        launch.controller.sceneChanged(to: .active)
        try await Task.sleep(for: .milliseconds(20))
        #expect(await phone.hardware.sheets == before + 1, "the sheet came straight back and the recovery key is out of reach")

        await phone.hardware.hand(to: .owner)
        await launch.controller.unlock(with: Self.code)
        #expect(await phone.hardware.sheets == before + 2)
        #expect(!launch.controller.isLocked)
    }

    @Test("The lock coming up again asks again")
    func theLockComingUpAsksAgain() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let launch = await relaunch(phone)
        let before = await phone.hardware.sheets
        await launch.controller.unlock(with: Self.code)
        #expect(!launch.controller.isLocked)

        launch.leaveAndComeBack()
        #expect(launch.controller.isLocked)
        await launch.controller.unlock(with: Self.code)

        #expect(!launch.controller.isLocked)
        #expect(await phone.hardware.sheets == before + 2)
    }

    @Test("A passed check is good for a minute, and a wait ends it")
    func aPassedCheckRunsOut() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let launch = await relaunch(phone)
        let before = await phone.hardware.sheets
        await launch.controller.unlock(with: "000000")
        phone.uptime.seconds += AppLockController.checkLasts
        await launch.controller.unlock(with: "000000")
        #expect(await phone.hardware.sheets == before + 2, "a check passed a minute ago still let a code be tried")

        for _ in 0..<3 { await launch.controller.unlock(with: "000000") }
        #expect(!launch.controller.phoneHasChecked, "a wait started and the passed check was kept")
    }

    @Test("Changing the code raises one sheet, only the new code opens, and Lock, Erase everything and Face ID alone stay as they were")
    func changingTheCode() async throws {
        let (phone, _) = try await phoneWithTheLockOn(biometrics: false)
        let launch = await relaunch(phone)
        await launch.controller.unlock(with: Self.code)
        #expect(await launch.controller.confirm(Self.code))
        #expect(await launch.controller.setDelay(300))
        #expect(await launch.controller.confirm(Self.code))
        #expect(await launch.controller.setEraseAfter(10))
        let before = await phone.hardware.sheets

        #expect(await launch.controller.confirm(Self.code))
        #expect(await launch.controller.turnOn(try lock("190482", biometrics: true), code: "190482"))

        #expect(await phone.hardware.sheets == before + 1)
        let kept = try #require(launch.controller.lock)
        #expect(kept.delay == 300)
        #expect(kept.eraseAfter == 10)
        #expect(!kept.usesBiometrics, "changing the code turned Face ID alone on")
        #expect(try await launch.keeper.sealed()?.usesBiometrics == false)

        let relaunched = await relaunch(phone)
        await relaunched.controller.unlock(with: Self.code)
        #expect(relaunched.controller.isLocked)
        await relaunched.controller.unlock(with: "190482")
        #expect(!relaunched.controller.isLocked)
    }

    @Test("Turning Face ID alone on raises one sheet, and turning the lock off raises one")
    func settingsChangesRaiseOneSheetEach() async throws {
        let (phone, _) = try await phoneWithTheLockOn()
        let launch = await relaunch(phone)
        await launch.controller.unlock(with: Self.code)
        await launch.session.load()

        var before = await phone.hardware.sheets
        #expect(await launch.controller.confirm(Self.code))
        #expect(await launch.controller.setBiometrics(true))
        #expect(await phone.hardware.sheets == before + 1)

        before = await phone.hardware.sheets
        #expect(await launch.controller.confirm(Self.code))
        #expect(await launch.controller.turnOff())
        #expect(await phone.hardware.sheets == before + 1)
        #expect(try await launch.keeper.sealed() == nil)
    }

    @Test("After the faces change, Face ID alone opens nothing, and entering the code turns it off rather than trusting the new faces")
    func newFacesTurnFaceIDAloneOff() async throws {
        let (phone, _) = try await phoneWithTheLockOn(biometrics: true)
        await phone.changeFaces()
        let launch = await relaunch(phone)
        let deadKey = try #require(try await launch.keeper.sealed()?.byBiometrics?.hardware)

        #expect(!launch.controller.offersBiometrics)
        #expect(launch.controller.biometricsChanged)
        await launch.controller.unlockWithBiometrics()
        #expect(launch.controller.isLocked)

        await launch.controller.unlock(with: Self.code)
        #expect(!launch.controller.isLocked)
        #expect(launch.controller.lock?.usesBiometrics == false)
        #expect(try await launch.keeper.sealed()?.byBiometrics == nil)
        #expect(!(await phone.hardware.held.contains(deadKey)))

        let relaunched = await relaunch(phone)
        #expect(!relaunched.controller.offersBiometrics)
        #expect(!relaunched.controller.biometricsChanged)
    }

    @Test("When the phone cannot say which faces are enrolled, entering the code leaves Face ID alone on")
    func unreadableFacesKeepFaceIDAlone() async throws {
        let (phone, _) = try await phoneWithTheLockOn(biometrics: true)
        phone.faces.enrolled = nil
        let launch = await relaunch(phone)

        #expect(!launch.controller.biometricsChanged)
        await launch.controller.unlock(with: Self.code)

        #expect(!launch.controller.isLocked)
        #expect(launch.controller.lock?.usesBiometrics == true)
        #expect(try await launch.keeper.sealed()?.byBiometrics != nil)
    }
}
