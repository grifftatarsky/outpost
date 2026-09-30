@testable import CarpenterKit
import CarpenterKitTesting
import CryptoKit
import Foundation
import Testing

@Suite("Outpost's own lock seals what this phone keeps")
struct OutpostsOwnLockSealsThisPhoneTests {
    private let rounds = 1_000

    @Test("The code opens what this phone keeps, and a wrong code opens nothing")
    func theCodeOpensIt() async throws {
        let hardware = FakeHardwareKeys()
        let (key, sealed) = try await Vault.create(
            code: "824193", usingBiometrics: false, hardware: hardware, rounds: rounds)

        let opened = try await Vault.open(sealed, with: "824193", hardware: hardware, reason: "")
        #expect(opened == key)
        await #expect(throws: VaultError.wrongCode) {
            _ = try await Vault.open(sealed, with: "824194", hardware: hardware, reason: "")
        }
    }

    @Test("A copy of what this phone keeps opens on no other phone, even with the code")
    func aCopyIsUselessOffThePhone() async throws {
        let hardware = FakeHardwareKeys()
        let (_, sealed) = try await Vault.create(
            code: "824193", usingBiometrics: false, hardware: hardware, rounds: rounds)

        let thief = FakeHardwareKeys()
        _ = try await thief.make(.code, requiringBiometrics: false)
        await #expect(throws: VaultError.wrongCode) {
            _ = try await Vault.open(sealed, with: "824193", hardware: thief, reason: "")
        }
    }

    @Test("Every code is worth a guess on the phone itself and nowhere else")
    func everyCodeCanOnlyBeTriedHere() async throws {
        let hardware = FakeHardwareKeys()
        let (_, sealed) = try await Vault.create(
            code: "1234", usingBiometrics: false, hardware: hardware, rounds: rounds)

        let thief = FakeHardwareKeys()
        _ = try await thief.make(.code, requiringBiometrics: false)
        for guess in 0..<40 {
            await #expect(throws: VaultError.wrongCode) {
                _ = try await Vault.open(sealed, with: String(format: "%04d", guess), hardware: thief, reason: "")
            }
        }
        #expect(
            try await Vault.open(sealed, with: "1234", hardware: hardware, reason: "") != nil,
            "the phone that made it can still open it")
    }

    @Test("Face ID releases the key, and refusing it releases nothing")
    func faceIDReleasesTheKey() async throws {
        let hardware = FakeHardwareKeys()
        let (key, sealed) = try await Vault.create(
            code: "824193", usingBiometrics: true, hardware: hardware, rounds: rounds)
        try #require(sealed.usesBiometrics)
        let whenItWasSetUp = await hardware.biometricChecks

        let opened = try await Vault.openWithBiometrics(sealed, hardware: hardware, reason: "")
        #expect(opened == key)
        #expect(
            await hardware.biometricChecks == whenItWasSetUp + 1,
            "the key came out of the enclave without the phone asking for a face")

        await hardware.allowBiometrics(false)
        await #expect(throws: HardwareKeyError.refused) {
            _ = try await Vault.openWithBiometrics(sealed, hardware: hardware, reason: "")
        }
        #expect(
            try await Vault.open(sealed, with: "824193", hardware: hardware, reason: "") == key,
            "the code still opens it when a face will not")
    }

    @Test("Turning Face ID off leaves only the code, and turning it on again does not change the code")
    func biometricsComeAndGo() async throws {
        let hardware = FakeHardwareKeys()
        let (key, sealed) = try await Vault.create(
            code: "824193", usingBiometrics: true, hardware: hardware, rounds: rounds)

        let without = try await Vault.withoutBiometrics(sealed, hardware: hardware)
        #expect(!without.usesBiometrics)
        await #expect(throws: VaultError.biometricsNotSet) {
            _ = try await Vault.openWithBiometrics(without, hardware: hardware, reason: "")
        }
        #expect(try await Vault.open(without, with: "824193", hardware: hardware, reason: "") == key)

        let again = try await Vault.addingBiometrics(to: without, key: key, hardware: hardware)
        #expect(try await Vault.openWithBiometrics(again, hardware: hardware, reason: "") == key)
        #expect(try await Vault.open(again, with: "824193", hardware: hardware, reason: "") == key)
    }

    @Test("Forgetting the code loses this phone's copy and nothing else")
    func forgettingTheCodeLosesOnlyThisPhone() async throws {
        let hardware = FakeHardwareKeys()
        let (_, sealed) = try await Vault.create(
            code: "824193", usingBiometrics: false, hardware: hardware, rounds: rounds)
        let vault = try JSONEncoder().encode(sealed)

        await hardware.forgetEverything()
        let readBack = try JSONDecoder().decode(SealedVaultKey.self, from: vault)
        await #expect(throws: HardwareKeyError.noSuchKey) {
            _ = try await Vault.open(readBack, with: "824193", hardware: hardware, reason: "")
        }
    }

    @Test("What this phone keeps is written sealed, and reads as nothing while the lock is shut")
    func theStateFileIsSealed() async throws {
        let folder = TestScratch.root.appending(path: "vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "state.json")
        let hardware = FakeHardwareKeys()
        let (key, _) = try await Vault.create(
            code: "824193", usingBiometrics: false, hardware: hardware, rounds: rounds)
        let vault = OpenVault(key: key)
        let store = SealedDocumentStore(around: FileDocumentStore(url: file), vault: vault)

        try await store.save(["Kitchen", "Lanterns"])
        let written = try Data(contentsOf: file)
        #expect(
            !String(decoding: written, as: UTF8.self).contains("Kitchen"),
            "a room's name was written where anybody holding the file could read it")
        #expect(try await store.load([String].self) == ["Kitchen", "Lanterns"])

        await vault.shut()
        await #expect(throws: VaultError.shut) { _ = try await store.load([String].self) }
        await #expect(throws: VaultError.shut) { try await store.save(["Anything"]) }

        await vault.open(with: key)
        #expect(try await store.load([String].self) == ["Kitchen", "Lanterns"])
    }

    @Test("A phone with no hardware key of its own seals nothing")
    func noHardwareNoSeal() async throws {
        let hardware = FakeHardwareKeys()
        await hardware.makeUnavailable()
        await #expect(throws: HardwareKeyError.unavailable) {
            _ = try await Vault.create(code: "824193", usingBiometrics: false, hardware: hardware, rounds: rounds)
        }
    }
}
