@testable import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("The device list tells the truth", .serialized)
struct TheDeviceListTellsTheTruthTests {
    @Test("The founding device says when it was made, not that it was always here")
    func theFoundingDeviceSaysWhenItWasMade() async throws {
        let clock = TestClock(now: TestSession.now)
        let session = TestSession.make(clock: clock)
        await session.load()
        try await session.createIdentity(displayName: "Griff")

        let device = try #require(session.devices.first)
        #expect(
            device.addedAt == TestSession.now,
            """
            The founding device self-certified at .distantPast, which the screen reads as "here \
            since you made this identity". That sentence was then true of every later device too, \
            because they all claimed the same instant.
            """)
    }

    @Test("A second device on the same account says when it arrived")
    func aSecondDeviceSaysWhenItArrived() async throws {
        let keychain = InMemoryKeychainStore()
        let clock = TestClock(now: TestSession.now)
        let first = TestSession.make(keychain: keychain, clock: clock)
        await first.load()
        try await first.createIdentity(displayName: "Griff")
        let founding = try #require(first.enrolment?.device.id)

        clock.advance(by: 86_400 * 5)
        try await keychain.remove(IdentityStore.deviceKey)
        let second = TestSession.make(keychain: keychain, clock: clock)
        await second.load()

        let sibling = try #require(second.enrolment?.device.id)
        #expect(sibling != founding, "the fixture did not make a second device")

        let listed = try #require(second.devices.first { $0.id == sibling })
        #expect(
            listed.addedAt == TestSession.now.addingTimeInterval(86_400 * 5),
            "a device that arrived five days later claims to have been here from the start")
    }

    @Test("A relaunch does not rewrite when a device arrived")
    func aRelaunchDoesNotRewriteWhenADeviceArrived() async throws {
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "devices-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = TestClock(now: TestSession.now)
        let session = TestSession.make(keychain: keychain, at: directory, clock: clock)
        await session.load()
        try await session.createIdentity(displayName: "Griff")
        let made = try #require(session.devices.first?.addedAt)

        clock.advance(by: 86_400 * 30)
        let relaunched = TestSession.make(keychain: keychain, at: directory, clock: clock)
        await relaunched.load()

        #expect(
            relaunched.devices.first?.addedAt == made,
            """
            Opening the app re-issued this device's own certificate, so "added" was really "last \
            launched". restoreLog minted a fresh certificate on every launch.
            """)
    }

    @Test("The device you are holding never reads as never used")
    func theDeviceYouAreHoldingNeverReadsAsUnused() async throws {
        let clock = TestClock(now: TestSession.now)
        let session = TestSession.make(clock: clock)
        await session.load()
        try await session.createIdentity(displayName: "Griff")

        let current = try #require(session.devices.first { $0.isCurrent })
        #expect(
            current.hasSpoken,
            """
            On a fresh install with name sharing off — the default — the founding device has \
            written no entries, so the list told the member "it has never been used, setup may not \
            have finished" about the device they were holding while reading it.
            """)
    }

    @Test("A device that has never written anything still reaches the list, and says so")
    func aSilentSiblingReachesTheList() async throws {
        let keychain = InMemoryKeychainStore()
        let relay = InMemoryEntrySync.Relay()
        let clock = TestClock(now: TestSession.now)

        let first = TestSession.make(keychain: keychain, clock: clock)
        first.syncDevices(through: InMemoryEntrySync(relay: relay))
        await first.load()
        try await first.createIdentity(displayName: "Griff")
        _ = try await first.createRoom(named: "Kitchen")

        try await keychain.remove(IdentityStore.deviceKey)
        let second = TestSession.make(keychain: keychain, clock: clock)
        second.syncDevices(through: InMemoryEntrySync(relay: relay))
        await second.load()
        let sibling = try #require(second.enrolment?.device.id)

        let deadline = Date().addingTimeInterval(5)
        while first.devices.count < 2 || second.devices.count < 2, Date() < deadline {
            await first.refreshDeviceSync()
            await second.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }

        let row = try #require(
            first.devices.first { $0.id == sibling },
            "a device that has written nothing still cannot be seen, or revoked, from its sibling")
        #expect(!row.hasSpoken, "the row claimed the silent device had sent something")
        #expect(row.addedAt != nil)
        #expect(second.devices.count == 2)
        #expect(
            first.persisted.certificates.contains { $0.device == sibling },
            "the certificate reached memory and was never written down, so a relaunch forgets the device")
    }
}
