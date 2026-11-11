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
import LocalAuthentication
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
            return VaultKeeper(keychain: keychain, hardware: SimulatorHardwareKeys(keychain: keychain), vault: gate)
        #else
            return VaultKeeper(keychain: keychain, hardware: SecureEnclaveKeys(service: service), vault: gate)
        #endif
    }()
}

#if targetEnvironment(simulator)
    struct SimulatorHardwareKeys: HardwareKeys {
        let keychain: any KeychainStore

        private struct Kept: Codable {
            let key: Data
            let rule: HardwareKeyRule
            let faces: Data?
        }

        private func slot(_ id: HardwareKeyID) -> KeychainKey { KeychainKey("simulated.hardware.\(id.rawValue)") }

        func make(_ id: HardwareKeyID, opensFor rule: HardwareKeyRule) async throws -> Data {
            let key = P256.KeyAgreement.PrivateKey()
            let kept = Kept(key: key.rawRepresentation, rule: rule, faces: rule == .enrolledFaces ? Self.faces() : nil)
            try await keychain.set(try JSONEncoder().encode(kept), for: slot(id), scope: .device)
            return key.publicKey.x963Representation
        }

        func agree(_ id: HardwareKeyID, with publicKey: Data, reason: String) async throws -> Data {
            guard let data = try await keychain.data(for: slot(id)) else { throw HardwareKeyError.noSuchKey }
            let kept = try JSONDecoder().decode(Kept.self, from: data)
            switch kept.rule {
            case .unlockedPhone:
                break
            case .ownerPresent:
                try await Self.ask(.deviceOwnerAuthentication, reason: reason)
            case .enrolledFaces:
                guard let faces = kept.faces, Self.faces() == faces else { throw HardwareKeyError.refused }
                try await Self.ask(.deviceOwnerAuthenticationWithBiometrics, reason: reason)
            }
            let key = try P256.KeyAgreement.PrivateKey(rawRepresentation: kept.key)
            let theirs = try P256.KeyAgreement.PublicKey(x963Representation: publicKey)
            return try key.sharedSecretFromKeyAgreement(with: theirs).withUnsafeBytes { Data($0) }
        }

        func remove(_ id: HardwareKeyID) async throws {
            try await keychain.remove(slot(id))
        }

        private static func faces() -> Data? {
            let context = LAContext()
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
            return context.domainState.biometry.stateHash
        }

        private static func ask(_ policy: LAPolicy, reason: String) async throws {
            guard !reason.isEmpty else { throw HardwareKeyError.unavailable }
            let context = LAContext()
            if policy == .deviceOwnerAuthenticationWithBiometrics { context.localizedFallbackTitle = "" }
            do {
                _ = try await context.evaluatePolicy(policy, localizedReason: reason)
            } catch let error as LAError where error.code == .passcodeNotSet {
                throw HardwareKeyError.noPasscode
            } catch {
                throw HardwareKeyError.refused
            }
        }
    }
#endif
