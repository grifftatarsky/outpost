import CarpenterApp
import CarpenterKeychain
import CarpenterKit
import CryptoKit
import Foundation
import Testing

@MainActor
@Suite("The lock's vault on the real keychain and real files", .serialized)
struct TheVaultOnTheRealKeychainTests {
    private struct KeysKeptInTheKeychain: HardwareKeys {
        let keychain: any KeychainStore

        private func slot(_ id: HardwareKeyID) -> KeychainKey { KeychainKey("test.hardware.\(id.rawValue)") }

        func make(_ id: HardwareKeyID, requiringBiometrics: Bool) async throws -> Data {
            let key = P256.KeyAgreement.PrivateKey()
            try await keychain.set(key.rawRepresentation, for: slot(id), scope: .device)
            return key.publicKey.x963Representation
        }

        func publicKey(of id: HardwareKeyID) async throws -> Data? {
            try await keychain.data(for: slot(id)).map {
                try P256.KeyAgreement.PrivateKey(rawRepresentation: $0).publicKey.x963Representation
            }
        }

        func agree(_ id: HardwareKeyID, with publicKey: Data, reason: String) async throws -> Data {
            guard let kept = try await keychain.data(for: slot(id)) else { throw HardwareKeyError.noSuchKey }
            let key = try P256.KeyAgreement.PrivateKey(rawRepresentation: kept)
            let theirs = try P256.KeyAgreement.PublicKey(x963Representation: publicKey)
            return try key.sharedSecretFromKeyAgreement(with: theirs).withUnsafeBytes { Data($0) }
        }

        func remove(_ id: HardwareKeyID) async throws {
            try await keychain.remove(slot(id))
        }
    }

    private struct Phone {
        let service = "com.microgpt.carpenter.tests.vault.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appending(path: "vault-\(UUID().uuidString)")

        var keychain: SystemKeychainStore { SystemKeychainStore(service: service) }

        var hardware: any HardwareKeys {
            SecureEnclaveKeys.isAvailable ? SecureEnclaveKeys(service: service) : KeysKeptInTheKeychain(keychain: keychain)
        }

        @MainActor func launch() -> (session: AppSession, keeper: VaultKeeper, gate: OpenVault) {
            let gate = OpenVault()
            let storage = SessionStorage(
                keychain: keychain,
                log: FileLogStore(url: directory.appending(path: "log")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json"))
            ).sealed(by: gate)
            return (
                AppSession(storage: storage),
                VaultKeeper(keychain: keychain, hardware: hardware, vault: gate, rounds: 1_000), gate
            )
        }
    }

    @Test("Turning the lock on seals the identity, a relaunch waits, the code opens it, and turning it off unseals")
    func theWholeLifeOfALock() async throws {
        let phone = Phone()
        try FileManager.default.createDirectory(at: phone.directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: phone.directory) }

        let first = phone.launch()
        await first.session.load()
        try await first.session.createIdentity(displayName: "Alice")
        let room = try await first.session.createRoom(named: "Lanterns")
        let plain = try #require(try await phone.keychain.data(for: IdentityStore.identityKey))
        #expect(!SealedKeychainStore.isSealed(plain))

        try await first.keeper.create(
            code: "482913", usingBiometrics: false, recovery: first.session.enrolment?.identity.vaultRecoverySecret)
        try await first.session.rewriteWhatThisPhoneKeeps()
        let sealed = try #require(try await phone.keychain.data(for: IdentityStore.identityKey))
        #expect(SealedKeychainStore.isSealed(sealed), "the identity is still in the clear in the real keychain")
        let file = try Data(contentsOf: phone.directory.appending(path: "state.json"))
        #expect(file.range(of: Data(room.rawValue.uuidString.utf8)) == nil, "the state file can still be read")

        let second = phone.launch()
        #expect(try await second.keeper.shutIfThereIsOne())
        await second.session.load()
        #expect(second.session.waitsForUnlock)
        #expect(second.session.enrolment == nil)
        #expect(try await second.keeper.open(with: "000000") == false)
        #expect(try await second.keeper.open(with: "482913"))
        await second.session.load()
        #expect(second.session.rooms.contains { $0.id == room })

        try second.gate.writeInTheClear()
        try await second.session.rewriteWhatThisPhoneKeeps()
        try await second.keeper.destroy()
        let unsealed = try #require(try await phone.keychain.data(for: IdentityStore.identityKey))
        #expect(!SealedKeychainStore.isSealed(unsealed))

        let third = phone.launch()
        #expect(try await third.keeper.shutIfThereIsOne() == false)
        await third.session.load()
        #expect(third.session.rooms.contains { $0.id == room })

        try await phone.keychain.removeAll(.device)
    }
}
