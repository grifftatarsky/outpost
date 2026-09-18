import CarpenterKit
import CarpenterKitTesting
import Foundation

@testable import CarpenterApp

enum TestSession {
    static let now = Date(timeIntervalSince1970: 1_786_635_000)

    static func storage(
        keychain: any KeychainStore = InMemoryKeychainStore(),
        at directory: URL? = nil,
        media: any MediaStore = MemoryMediaStore()
    ) -> SessionStorage {
        let root =
            directory
            ?? URL.temporaryDirectory.appending(path: "carpenter-test-\(UUID().uuidString)")

        return SessionStorage(
            keychain: keychain,
            log: FileLogStore(url: root.appending(path: "log.carpenter")),
            documents: FileDocumentStore(url: root.appending(path: "state.json")),
            media: media
        )
    }

    @MainActor
    static func make(
        keychain: any KeychainStore = InMemoryKeychainStore(),
        at directory: URL? = nil,
        denyList: DenyList = .empty,
        media: any MediaStore = MemoryMediaStore(),
        clock: any Clock = TestClock(now: now)
    ) -> AppSession {
        AppSession(
            storage: storage(keychain: keychain, at: directory, media: media),
            clock: clock, denyList: denyList)
    }
}
