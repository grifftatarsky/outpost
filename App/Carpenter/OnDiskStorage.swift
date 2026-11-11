import CarpenterApp
import CarpenterCloudKit
import CarpenterKeychain
import CloudKit
import CarpenterKit
import CryptoKit
import CarpenterMedia
import CarpenterUI
import OSLog
import Intents
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

extension SessionStorage {
    static func onDisk(profile: TestProfile? = nil) -> SessionStorage {
        let container = TestProfileWorld.container(for: profile)
        let directory = StorageLocation.directory(container: container)
        Diagnostics.sync.notice(
            "storage: \(directory.path, privacy: .public) appGroup=\(AppGroup.available, privacy: .public)")

        let protection = profile == nil ? ProtectionDial.main : ProtectionDial()
        let system = SystemKeychainStore(
            service: container, accessGroup: SharedKeychain.group, protection: protection)
        let keychain: any KeychainStore = profile == nil ? system : DeviceOnlyKeychainStore(system)

        let storage = SessionStorage(
            keychain: keychain,
            log: FileLogStore(url: directory.appending(path: StorageLocation.logName), protection: protection),
            documents: FileDocumentStore(
                url: directory.appending(path: StorageLocation.stateName), protection: protection),
            media: FileMediaStore(directory: FileMediaStore.url(inDirectory: directory), protection: protection),
            protection: protection,
            locations: keptLocations(container: container, directory: directory, shared: profile == nil),
            settings: profile == nil ? keptSettings : []
        )
        return profile == nil ? storage.sealed(by: LockVault.gate) : storage
    }

    private static func keptLocations(container: String, directory: URL, shared: Bool) -> [URL] {
        let own = [directory, StorageLocation.fallback(container: container)]
        guard shared else { return own }
        return own + [FocusFilterStore.directory, ScratchSpace.shared.directory].compactMap { $0 }
    }

    private static let keptSettings = [
        KeptSetting(key: MediaLoader.revealedKey),
        KeptSetting(suite: AppGroup.identifier, key: FocusFilterStore.filterKey),
    ]
}

enum LockVault {
    static let gate = OpenVault()

    static let keeper: VaultKeeper = {
        let service = TestProfileWorld.container(for: nil)
        let keychain = SystemKeychainStore(service: service, accessGroup: SharedKeychain.group, protection: .main)
        #if targetEnvironment(simulator)
            return VaultKeeper(
                keychain: keychain, hardware: SimulatorHardwareKeys(keychain: keychain), vault: gate,
                checksBiometricsItself: false)
        #else
            return VaultKeeper(keychain: keychain, hardware: SecureEnclaveKeys(service: service), vault: gate)
        #endif
    }()
}

#if targetEnvironment(simulator)
    struct SimulatorHardwareKeys: HardwareKeys {
        let keychain: any KeychainStore

        private func slot(_ id: HardwareKeyID) -> KeychainKey { KeychainKey("simulated.hardware.\(id.rawValue)") }

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
#endif
