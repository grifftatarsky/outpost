import CarpenterKit
import Foundation

// MARK: Erasing everything this phone keeps

public struct KeptSetting: Hashable, Sendable {
    public let suite: String?
    public let key: String

    public init(suite: String? = nil, key: String) {
        self.suite = suite
        self.key = key
    }
}

extension AppSession {
    public func eraseWhatThisPhoneKeeps() async {
        incomingTask?.cancel()
        incomingTask = nil
        deviceSync = nil

        do {
            try await storage.keychain.removeAll()
        } catch {
            Diagnostics.identity.error(
                "erase: the keychain would not empty (\(String(describing: error), privacy: .public))")
        }
        await eraseFiles()
        for setting in storage.settings {
            (setting.suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard).removeObject(forKey: setting.key)
        }

        enrolment = nil
        chains = [:]
        unsavedRecoveryKey = nil
        replica = Replica()
        persisted = PersistedState()
        rooms = []
    }

    private func eraseFiles() async {
        let stores: [(String, () async throws -> Void)] = [
            ("the log", storage.log.removeAll),
            ("the photos", storage.media.removeAll),
            ("the state", storage.documents.clear),
        ]
        for (what, erase) in stores {
            do { try await erase() } catch {
                Diagnostics.identity.error(
                    "erase: could not remove \(what, privacy: .public) (\(String(describing: error), privacy: .public))")
            }
        }
        for location in storage.locations {
            do {
                try FileManager.default.removeItem(at: location)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
            } catch {
                Diagnostics.identity.error(
                    "erase: could not remove a place this phone keeps things (\(String(describing: error), privacy: .public))")
            }
        }
    }
}
