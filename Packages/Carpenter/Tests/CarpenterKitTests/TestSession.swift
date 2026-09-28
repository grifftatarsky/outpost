import CarpenterKit
import CarpenterKitTesting
import Foundation

@testable import CarpenterApp

enum TestSession {
    static let now = Date(timeIntervalSince1970: 1_786_635_000)

    static func storage(
        keychain: any KeychainStore = InMemoryKeychainStore(),
        at directory: URL? = nil,
        media: any MediaStore = MemoryMediaStore(),
        protection: ProtectionDial = ProtectionDial()
    ) -> SessionStorage {
        let root =
            directory
            ?? TestScratch.root.appending(path: "carpenter-test-\(UUID().uuidString)")

        return SessionStorage(
            keychain: keychain,
            log: FileLogStore(url: root.appending(path: "log.carpenter"), protection: protection),
            documents: FileDocumentStore(url: root.appending(path: "state.json"), protection: protection),
            media: media,
            protection: protection
        )
    }

    @MainActor
    static func make(
        keychain: any KeychainStore = InMemoryKeychainStore(),
        at directory: URL? = nil,
        denyList: DenyList = .empty,
        media: any MediaStore = MemoryMediaStore(),
        protection: ProtectionDial = ProtectionDial(),
        clock: any Clock = TestClock(now: now)
    ) -> AppSession {
        AppSession(
            storage: storage(keychain: keychain, at: directory, media: media, protection: protection),
            clock: clock, denyList: denyList)
    }
}
