import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@Suite("Device sync", .serialized)
@MainActor
struct EntrySyncTests {
    private func pair() -> (relay: InMemoryEntrySync.Relay, keychain: InMemoryKeychainStore) {
        (InMemoryEntrySync.Relay(), InMemoryKeychainStore())
    }

    private func settle(_ session: AppSession, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return }
            await session.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    @Test("What one device writes reaches the other")
    func writesReachTheOtherDevice() async throws {
        let (relay, keychain) = pair()

        let original = TestSession.make(keychain: keychain)
        let originalSync = InMemoryEntrySync(relay: relay)
        original.syncDevices(through: originalSync)
        await original.load()
        try await original.createIdentity(displayName: "Griff")

        try await keychain.remove(IdentityStore.deviceKey)
        let incoming = TestSession.make(keychain: keychain)
        let incomingSync = InMemoryEntrySync(relay: relay)
        incoming.syncDevices(through: incomingSync)
        await incoming.load()

        let room = try await original.createRoom(named: "Kitchen")
        try await original.send("door code changed", to: room)

        await settle(incoming) {
            incoming.state == .ready && incoming.rooms.first?.name == "Kitchen"
                && incoming.messages(in: room).contains { $0.body == "door code changed" }
        }

        #expect(incoming.state == .ready)
        #expect(incoming.viewer.displayName == "Griff")
        #expect(incoming.rooms.first?.name == "Kitchen")
        #expect(incoming.messages(in: room).contains { $0.body == "door code changed" })
    }

    @Test("Opening the app is enough, even if nothing announced itself")
    func openingTheAppFetchesWithoutBeingTold() async throws {
        let relay = InMemoryEntrySync.Relay(announces: false)
        let keychain = InMemoryKeychainStore()

        let original = TestSession.make(keychain: keychain)
        let originalSync = InMemoryEntrySync(relay: relay)
        original.syncDevices(through: originalSync)
        await original.load()
        try await original.createIdentity(displayName: "Griff")

        try await keychain.remove(IdentityStore.deviceKey)
        let incoming = TestSession.make(keychain: keychain)
        let incomingSync = InMemoryEntrySync(relay: relay)
        incoming.syncDevices(through: incomingSync)
        await incoming.load()

        let room = try await original.createRoom(named: "Kitchen")
        try await original.send("door code changed", to: room)

        #expect(
            incoming.messages(in: room).isEmpty,
            "arrived without being fetched — this relay does not announce")

        await settle(incoming) {
            incoming.rooms.first?.name == "Kitchen"
                && incoming.messages(in: room).contains { $0.body == "door code changed" }
        }

        #expect(incoming.rooms.first?.name == "Kitchen")
        #expect(incoming.messages(in: room).contains { $0.body == "door code changed" })
    }

    @Test("A device does not receive its own writes back")
    func ownWritesAreNotEchoed() async throws {
        let relay = InMemoryEntrySync.Relay()
        let session = TestSession.make()
        let sync = InMemoryEntrySync(relay: relay)
        session.syncDevices(through: sync)
        await session.load()
        try await session.createIdentity(displayName: "Griff")

        let before = session.entryCount
        try await Task.sleep(for: .milliseconds(100))
        #expect(session.entryCount == before, "took its own entries back in")
    }
}
