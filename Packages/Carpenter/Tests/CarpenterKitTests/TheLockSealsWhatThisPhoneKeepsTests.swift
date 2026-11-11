@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import CryptoKit
import Foundation
import Testing

@MainActor
@Suite("With the lock on, what this phone keeps is sealed, and the app waits while it is shut", .serialized, .tags(.crypto))
struct TheLockSealsWhatThisPhoneKeepsTests {
    private struct Phone {
        let directory = TestScratch.root.appending(path: "vault-\(UUID().uuidString)")
        let keychain = InMemoryKeychainStore()
        let hardware = FakeHardwareKeys()
        let vault = OpenVault()

        var keeper: VaultKeeper { VaultKeeper(keychain: keychain, hardware: hardware, vault: vault, rounds: 1_000) }
        var stateFile: URL { directory.appending(path: "state.json") }

        @MainActor func session() -> AppSession {
            AppSession(
                storage: TestSession.storage(keychain: keychain, at: directory).sealed(by: vault),
                clock: TestClock(now: TestSession.now), denyList: .empty)
        }

        func sealedKeys() async throws -> [Bool] {
            var found: [Bool] = []
            for key in [IdentityStore.identityKey, IdentityStore.deviceKey] {
                found.append(SealedKeychainStore.isSealed(try #require(try await keychain.data(for: key))))
            }
            return found
        }
    }

    private func phoneWithARoom() async throws -> (phone: Phone, session: AppSession, room: RoomID) {
        let phone = Phone()
        let session = phone.session()
        await session.load()
        try await session.createIdentity(displayName: "Alice")
        let room = try await session.createRoom(named: "Lanterns")
        try await session.send("the mooring mast drawings", to: room)
        return (phone, session, room)
    }

    private func lockOn(_ phone: Phone, _ session: AppSession, code: String = "824193") async throws {
        try await phone.keeper.create(
            code: code, usingBiometrics: false, recovery: session.enrolment?.identity.vaultRecoverySecret)
        try await session.rewriteWhatThisPhoneKeeps()
    }

    @Test("Before the lock is on, nothing is sealed and nothing changes")
    func withoutALockNothingIsSealed() async throws {
        let (phone, _, room) = try await phoneWithARoom()
        #expect(try await phone.sealedKeys() == [false, false])
        #expect(try Data(contentsOf: phone.stateFile).range(of: Data(room.rawValue.uuidString.utf8)) != nil)
    }

    @Test("Turning the lock on seals the state file, the identity, the device key and the room keys")
    func turningItOnSeals() async throws {
        let (phone, session, room) = try await phoneWithARoom()
        try await lockOn(phone, session)

        #expect(try await phone.sealedKeys() == [true, true])
        for number in session.persisted.epochs[room] ?? [] {
            let kept = try #require(
                try await phone.keychain.data(for: AppSession.epochKey(room, EpochNumber(rawValue: number))))
            #expect(SealedKeychainStore.isSealed(kept), "a room key was left in the clear")
        }
        let file = try Data(contentsOf: phone.stateFile)
        #expect(file.range(of: Data(room.rawValue.uuidString.utf8)) == nil, "which rooms this phone is in can be read in the file")
        #expect(session.persisted.keptIsSealed)
    }

    @Test("While it is shut the app reads nothing, writes nothing and does not take the phone for an empty one")
    func whileShutTheAppWaits() async throws {
        let (phone, session, _) = try await phoneWithARoom()
        try await lockOn(phone, session)
        phone.vault.shut()
        let fileBefore = try Data(contentsOf: phone.stateFile)
        let identityBefore = try await phone.keychain.data(for: IdentityStore.identityKey)

        let reopened = phone.session()
        await reopened.load()

        #expect(reopened.waitsForUnlock)
        #expect(reopened.enrolment == nil)
        #expect(reopened.storageIsSealed)
        if case .checkingForRegistration = reopened.state { Issue.record("a shut phone was taken for a new one") }
        await #expect(throws: VaultError.shut) { try await reopened.rewriteWhatThisPhoneKeeps() }
        #expect(try Data(contentsOf: phone.stateFile) == fileBefore)
        #expect(try await phone.keychain.data(for: IdentityStore.identityKey) == identityBefore)
    }

    @Test("The code opens it and everything is there; a wrong code opens nothing")
    func theCodeOpensIt() async throws {
        let (phone, session, room) = try await phoneWithARoom()
        try await lockOn(phone, session)
        phone.vault.shut()

        #expect(try await phone.keeper.open(with: "824194") == false)
        #expect(phone.vault.isShut)
        #expect(try await phone.keeper.open(with: "824193"))

        let reopened = phone.session()
        await reopened.load()
        #expect(!reopened.waitsForUnlock)
        #expect(reopened.rooms.contains { $0.id == room && $0.name == "Lanterns" })
        #expect(reopened.transcript(in: room).contains { item in
            if case .message(let message) = item { return message.body == "the mooring mast drawings" }
            return false
        })
    }

    @Test("A fresh launch with a vault on the phone starts shut, before anything is read")
    func aFreshLaunchStartsShut() async throws {
        let (phone, session, _) = try await phoneWithARoom()
        try await lockOn(phone, session)

        let afterRelaunch = OpenVault()
        let keeper = VaultKeeper(keychain: phone.keychain, hardware: phone.hardware, vault: afterRelaunch, rounds: 1_000)
        #expect(try await keeper.shutIfThereIsOne())
        #expect(afterRelaunch.isShut)
    }

    @Test("The recovery key opens it when the code is forgotten, and somebody else's does not")
    func theRecoveryKeyOpensIt() async throws {
        let (phone, session, _) = try await phoneWithARoom()
        let text = try #require(session.recoveryKeyText())
        try await lockOn(phone, session)
        phone.vault.shut()

        #expect(try await phone.keeper.openWithRecovery(Identity.generate().vaultRecoverySecret) == false)
        #expect(phone.vault.isShut)
        let secret = try RecoveryKey.secret(from: text).identity.vaultRecoverySecret
        #expect(try await phone.keeper.openWithRecovery(secret))
        #expect(phone.vault.isOpen)
    }

    @Test("Turning the lock off puts everything back in the clear and leaves no vault behind")
    func turningItOffUnseals() async throws {
        let (phone, session, room) = try await phoneWithARoom()
        try await lockOn(phone, session)

        try phone.vault.writeInTheClear()
        try await session.rewriteWhatThisPhoneKeeps()
        try await phone.keeper.destroy()

        #expect(try await phone.sealedKeys() == [false, false])
        #expect(try await phone.keeper.sealed() == nil)
        #expect(!session.persisted.keptIsSealed)
        let plain = AppSession(
            storage: TestSession.storage(keychain: phone.keychain, at: phone.directory),
            clock: TestClock(now: TestSession.now), denyList: .empty)
        await plain.load()
        #expect(plain.rooms.contains { $0.id == room })
    }

    @Test("A seal that stopped half-way is finished the next time the phone is opened")
    func aHalfFinishedSealIsFinished() async throws {
        let (phone, session, _) = try await phoneWithARoom()
        try await phone.keeper.create(
            code: "824193", usingBiometrics: false, recovery: session.enrolment?.identity.vaultRecoverySecret)
        #expect(try await phone.sealedKeys() == [false, false], "precondition: the app stopped before sealing")

        let reopened = phone.session()
        await reopened.load()

        #expect(try await phone.sealedKeys() == [true, true])
        #expect(reopened.persisted.keptIsSealed)
    }

    @Test("A sealed key moved into another key's place opens nothing")
    func aSealedKeyOpensOnlyInItsOwnPlace() async throws {
        let (phone, session, _) = try await phoneWithARoom()
        try await lockOn(phone, session)
        let identity = try #require(try await phone.keychain.data(for: IdentityStore.identityKey))
        try await phone.keychain.set(identity, for: IdentityStore.deviceKey, scope: .device)

        let sealing = SealedKeychainStore(around: phone.keychain, vault: phone.vault)
        await #expect(throws: (any Error).self) { _ = try await sealing.data(for: IdentityStore.deviceKey) }
    }

    @Test("A copy of the files and the keychain opens on no other phone, even with the code")
    func aCopyOpensNowhereElse() async throws {
        let (phone, session, _) = try await phoneWithARoom()
        try await lockOn(phone, session)

        let thief = VaultKeeper(keychain: phone.keychain, hardware: FakeHardwareKeys(), vault: OpenVault(), rounds: 1_000)
        await #expect(throws: (any Error).self) { _ = try await thief.open(with: "824193") }
    }

    @Test("With a vault, the lock itself keeps nothing that says whether a code is right")
    func theLockKeepsNoVerifier() throws {
        let lock = try AppLock.make("824193", as: .digits, usesBiometrics: false).withoutAVerifier
        #expect(!lock.matches("824193"))
        let kept = try JSONEncoder().encode(lock)
        #expect(try JSONDecoder().decode(AppLock.self, from: kept) == lock)
    }

    @Test("Changing the code keeps what is sealed and the old code stops opening it")
    func changingTheCode() async throws {
        let (phone, session, _) = try await phoneWithARoom()
        try await lockOn(phone, session)

        try await phone.keeper.changeCode(to: "190482")
        phone.vault.shut()

        #expect(try await phone.keeper.open(with: "824193") == false)
        #expect(try await phone.keeper.open(with: "190482"))
        let reopened = phone.session()
        await reopened.load()
        #expect(reopened.enrolment != nil)
    }
}
