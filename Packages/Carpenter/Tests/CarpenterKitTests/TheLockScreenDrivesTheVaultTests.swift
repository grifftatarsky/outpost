@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
@testable import CarpenterUI
import Foundation
import SwiftUI
import Testing

@MainActor
@Suite("The lock screen opens, shuts, makes and removes the vault", .serialized, .tags(.crypto))
struct TheLockScreenDrivesTheVaultTests {
    private final class Uptime: @unchecked Sendable {
        var seconds: TimeInterval = 1_000
        var moment: LockMoment { LockMoment(boot: "boot-one", uptime: seconds) }
    }

    private struct Faces: Biometrics {
        var name: String? { "Face ID" }
        func state() -> Data? { Data([1]) }
        func passcodeIsSet() -> Bool { true }
        func evaluate(reason: String) async -> Bool { true }
    }

    private struct Phone {
        let directory = TestScratch.root.appending(path: "lock-vault-\(UUID().uuidString)")
        let keychain = InMemoryKeychainStore()
        let hardware = FakeHardwareKeys()
        let uptime = Uptime()
    }

    @MainActor
    private struct Launch {
        let phone: Phone
        let vault = OpenVault()
        let session: AppSession
        let controller: AppLockController
        let keeper: VaultKeeper

        init(_ phone: Phone) {
            self.phone = phone
            let vault = vault
            let keeper = VaultKeeper(keychain: phone.keychain, hardware: phone.hardware, vault: vault, rounds: 1_000)
            let session = AppSession(
                storage: TestSession.storage(keychain: phone.keychain, at: phone.directory).sealed(by: vault),
                clock: TestClock(now: TestSession.now), denyList: .empty)
            let uptime = phone.uptime
            let controller = AppLockController(
                store: AppLockStore(keychain: phone.keychain), vault: keeper, biometrics: Faces(),
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
        }

        func open() async {
            _ = try? await keeper.shutIfThereIsOne()
            await controller.load()
            await session.load()
        }

        func identityIsSealed() async throws -> Bool {
            SealedKeychainStore.isSealed(try #require(try await phone.keychain.data(for: IdentityStore.identityKey)))
        }
    }

    private func lock(_ code: String, biometrics: Bool = false) throws -> AppLock {
        try AppLock.make(code, as: .digits, usesBiometrics: biometrics, biometricState: Data([1]), rounds: 1_000)
    }

    private func phoneWithTheLockOn(biometrics: Bool = false) async throws -> (Phone, RoomID, String) {
        let phone = Phone()
        let first = Launch(phone)
        await first.open()
        try await first.session.createIdentity(displayName: "Alice")
        let text = try #require(first.session.recoveryKeyText())
        let room = try await first.session.createRoom(named: "Lanterns")
        #expect(await first.controller.turnOn(try lock("482913", biometrics: biometrics), code: "482913"))
        #expect(try await first.identityIsSealed(), "turning the lock on left the identity in the clear")
        return (phone, room, text)
    }

    @Test("Turning the lock on seals what the phone keeps, and the lock keeps nothing that says whether a code is right")
    func turningItOn() async throws {
        let (phone, _, _) = try await phoneWithTheLockOn()
        let kept = try #require(try await AppLockStore(keychain: phone.keychain).load())
        #expect(!kept.matches("482913"))
    }

    @Test("After a relaunch the app waits behind the lock, a wrong code opens nothing, and the right one brings everything back")
    func aRelaunchWaitsForTheCode() async throws {
        let (phone, room, _) = try await phoneWithTheLockOn()
        let relaunched = Launch(phone)
        await relaunched.open()

        #expect(relaunched.controller.isLocked)
        #expect(relaunched.session.waitsForUnlock)
        #expect(relaunched.session.enrolment == nil)

        await relaunched.controller.unlock(with: "000000")
        #expect(relaunched.controller.isLocked)
        #expect(relaunched.vault.isShut)

        await relaunched.controller.unlock(with: "482913")
        #expect(!relaunched.controller.isLocked)
        await relaunched.session.load()
        #expect(relaunched.session.rooms.contains { $0.id == room })
    }

    @Test("Coming back after the lock's delay shuts the vault again")
    func comingBackLateShutsIt() async throws {
        let (phone, _, _) = try await phoneWithTheLockOn()
        let launch = Launch(phone)
        await launch.open()
        await launch.controller.unlock(with: "482913")
        try #require(launch.vault.isOpen)

        launch.controller.sceneChanged(to: .background)
        phone.uptime.seconds += 3_600
        launch.controller.sceneChanged(to: .active)

        #expect(launch.controller.isLocked)
        #expect(launch.vault.isShut)
        #expect(launch.session.storageIsSealed)
    }

    @Test("Turning the lock off puts everything back in the clear and removes the vault")
    func turningItOff() async throws {
        let (phone, room, _) = try await phoneWithTheLockOn()
        let launch = Launch(phone)
        await launch.open()
        await launch.controller.unlock(with: "482913")
        await launch.session.load()

        #expect(await launch.controller.confirm("482913"))
        #expect(await launch.controller.turnOff())

        #expect(try await launch.identityIsSealed() == false)
        #expect(try await launch.keeper.sealed() == nil)
        #expect(!launch.vault.isInUse)
        let plain = Launch(phone)
        await plain.open()
        #expect(!plain.controller.isLocked)
        #expect(plain.session.rooms.contains { $0.id == room })
    }

    @Test("With the code forgotten, the recovery key opens the phone, turns the lock off and loses nothing")
    func theRecoveryKeyGetsBackIn() async throws {
        let (phone, room, text) = try await phoneWithTheLockOn()
        let relaunched = Launch(phone)
        await relaunched.open()

        #expect(await relaunched.controller.unlock(withRecoveryKey: "not a key") == false)
        #expect(relaunched.vault.isShut)
        #expect(await relaunched.controller.unlock(withRecoveryKey: text))

        #expect(relaunched.controller.lock == nil)
        #expect(try await relaunched.identityIsSealed() == false)
        #expect(relaunched.session.rooms.contains { $0.id == room })
    }

    @Test("Changing the code keeps everything, and only the new code opens it")
    func changingTheCode() async throws {
        let (phone, room, _) = try await phoneWithTheLockOn()
        let launch = Launch(phone)
        await launch.open()
        await launch.controller.unlock(with: "482913")
        await launch.session.load()
        #expect(await launch.controller.confirm("482913"))
        #expect(await launch.controller.turnOn(try lock("190482"), code: "190482"))

        let relaunched = Launch(phone)
        await relaunched.open()
        await relaunched.controller.unlock(with: "482913")
        #expect(relaunched.controller.isLocked)
        await relaunched.controller.unlock(with: "190482")
        #expect(!relaunched.controller.isLocked)
        await relaunched.session.load()
        #expect(relaunched.session.rooms.contains { $0.id == room })
    }

    @Test("Face ID opens the vault through the phone's own key, and a refused face opens nothing")
    func faceIDOpensIt() async throws {
        let (phone, _, _) = try await phoneWithTheLockOn(biometrics: true)
        let relaunched = Launch(phone)
        await relaunched.open()

        await phone.hardware.hand(to: .somebodyWhoFails)
        await relaunched.controller.unlockWithBiometrics()
        #expect(relaunched.controller.isLocked)
        #expect(relaunched.vault.isShut)

        await phone.hardware.hand(to: .owner)
        await relaunched.controller.unlockWithBiometrics()
        #expect(!relaunched.controller.isLocked)
        #expect(relaunched.vault.isOpen)
    }

    @Test("A vault left behind when the lock was never saved is cleared, and nothing was sealed with it")
    func anOrphanVaultIsCleared() async throws {
        let phone = Phone()
        let first = Launch(phone)
        await first.open()
        try await first.session.createIdentity(displayName: "Alice")
        _ = try await first.keeper.make(code: "482913", usingBiometrics: false, recovery: nil, reason: "Turn on the lock")

        let relaunched = Launch(phone)
        await relaunched.open()

        #expect(!relaunched.controller.isLocked)
        #expect(!relaunched.vault.isInUse)
        #expect(try await relaunched.keeper.sealed() == nil)
        #expect(relaunched.session.enrolment != nil)
    }
}
