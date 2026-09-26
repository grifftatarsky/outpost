import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@Suite("Settings changed on another of your devices", .serialized)
@MainActor
struct SettingsFromAnotherDeviceTests {
    private func twoDevices() async throws -> (first: AppSession, second: AppSession, clock: TestClock) {
        let keychain = InMemoryKeychainStore()
        let relay = InMemoryEntrySync.Relay()
        let clock = TestClock(now: TestSession.now)

        let first = TestSession.make(keychain: keychain, clock: clock)
        first.syncDevices(through: InMemoryEntrySync(relay: relay))
        await first.load()
        try await first.createIdentity(displayName: "Griff")
        let room = try await first.createRoom(named: "Kitchen")
        try await first.send("hello", to: room)

        try await keychain.remove(IdentityStore.deviceKey)
        let second = TestSession.make(keychain: keychain, clock: clock)
        second.syncDevices(through: InMemoryEntrySync(relay: relay))
        await second.load()
        await second.settleDeviceSync { second.messages(in: room).contains { $0.body == "hello" } }
        return (first, second, clock)
    }

    @Test("A nickname set on another device shows here without waiting for anything else")
    func aNicknameArrivesAtOnce() async throws {
        let (first, second, clock) = try await twoDevices()
        let someone = ParticipantID(rawValue: Data(repeating: 9, count: 32))
        _ = second.projection

        clock.advance(by: 60)
        await first.setNickname("Bobby", for: someone)
        await first.settleDeviceSync()
        await second.settleDeviceSync { second.persisted.preferences.nickname(for: someone) == "Bobby" }

        #expect(second.persisted.preferences.nickname(for: someone) == "Bobby", "precondition: the setting arrived")
        #expect(
            second.projection.member(someone).displayName == "Bobby",
            """
            The nickname arrived and the screen kept the old name. Settings merged from another \
            device reached the saved state but not the projection, which held names from before \
            the merge until something unrelated changed the log.
            """)
    }
}
