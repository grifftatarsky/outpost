import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("A message that cannot be sent", .serialized)
@MainActor
struct SendFailureTests {
    private func scratch() -> URL {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-send-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func session(keychain: any KeychainStore) -> AppSession {
        let directory = scratch()
        return AppSession(
            storage: SessionStorage(
                keychain: keychain,
                log: FileLogStore(url: directory.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json"))
            ),
            clock: TestClock(now: TestSession.now)
        )
    }

    @Test("A refused keychain access group does not lose the message")
    func refusedGroupStillSends() async throws {
        let keychain = RefusingGroupKeychainStore(sharedGroupRefused: true)
        let alice = session(keychain: keychain)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("this must not vanish", to: room)

        #expect(
            await keychain.refusals > 0,
            "precondition: the shared group was actually exercised and refused")
        #expect(
            alice.messages(in: room).contains { $0.body == "this must not vanish" },
            "the message was lost between the composer and the log")
    }

    @Test("A message written under a refused group survives a relaunch")
    func refusedGroupPersists() async throws {
        let keychain = RefusingGroupKeychainStore(sharedGroupRefused: true)
        let directory = scratch()

        func build() -> AppSession {
            AppSession(
                storage: SessionStorage(
                    keychain: keychain,
                    log: FileLogStore(url: directory.appending(path: "log.carpenter")),
                    documents: FileDocumentStore(url: directory.appending(path: "state.json"))
                ),
                clock: TestClock(now: TestSession.now)
            )
        }

        let first = build()
        await first.load()
        try await first.createIdentity(displayName: "Alice")
        let room = try await first.createRoom(named: "Hangar 7")
        try await first.send("still here tomorrow", to: room)

        let second = build()
        await second.load()
        #expect(
            second.messages(in: room).contains { $0.body == "still here tomorrow" },
            "the message rendered once and was gone on relaunch")
    }

    @Test("Sending with no identity throws rather than failing quietly")
    func sendWithoutIdentityThrows() async throws {
        let alice = session(keychain: InMemoryKeychainStore())
        await alice.load()

        await #expect(throws: AppSessionError.self) {
            try await alice.send("nowhere to go", to: ConversationID.room(UUID()))
        }
    }
}
