@testable import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("Naming your own devices", .serialized)
@MainActor
struct NamingYourDevicesTests {
    private func session() async throws -> AppSession {
        let made = TestSession.make(keychain: InMemoryKeychainStore())
        await made.load()
        try await made.createIdentity(displayName: "Griff")
        return made
    }

    @Test("A device takes the name its hardware gives, once")
    func aDeviceTakesItsHardwareName() async throws {
        let session = try await session()
        let me = try #require(session.enrolment?.device.id)

        await session.nameThisDeviceIfUnnamed("iPhone17,1")
        #expect(session.deviceName(me) == "iPhone17,1")

        await session.nameThisDeviceIfUnnamed("iPhone99,9")
        #expect(
            session.deviceName(me) == "iPhone17,1",
            """
            A later launch overwrote a name the member had. The hardware name is a starting point, \
            not something the app keeps reapplying.
            """)
    }

    @Test("A name the member chose replaces it and shows in the list")
    func aChosenNameReplacesIt() async throws {
        let session = try await session()
        let me = try #require(session.enrolment?.device.id)
        await session.nameThisDeviceIfUnnamed("iPhone17,1")

        await session.setDeviceName("The one in my pocket", for: me)

        #expect(session.deviceName(me) == "The one in my pocket")
        let listed = try #require(session.devices.first { $0.id == me })
        #expect(listed.name == "The one in my pocket", "the list did not show the name")
        #expect(
            listed.shortCode.count == 6,
            "the code went away with the name, and it is how a device is matched across accounts")
    }

    @Test("Clearing a name puts the code back rather than leaving a blank row")
    func clearingANamePutsTheCodeBack() async throws {
        let session = try await session()
        let me = try #require(session.enrolment?.device.id)
        await session.setDeviceName("Old laptop", for: me)
        await session.setDeviceName("   ", for: me)

        #expect(session.deviceName(me) == nil)
        #expect(
            session.devices.first { $0.id == me }?.isNamed == false,
            "a device whose name was cleared still claimed to have one, so the row would be empty")
    }

    @Test("A name is trimmed and bounded")
    func aNameIsTrimmedAndBounded() async throws {
        let session = try await session()
        let me = try #require(session.enrolment?.device.id)

        await session.setDeviceName("  Kitchen iPad  ", for: me)
        #expect(session.deviceName(me) == "Kitchen iPad")

        await session.setDeviceName(String(repeating: "n", count: 500), for: me)
        #expect(
            (session.deviceName(me)?.count ?? 0) <= MemberPreferences.deviceNameLimit,
            "an unbounded name goes into the sibling feed and into every row that draws it")
    }

    @Test("Names reach the member's own devices and nobody else")
    func namesReachOwnDevicesOnly() async throws {
        let keychain = InMemoryKeychainStore()
        let relay = InMemoryEntrySync.Relay()

        let first = TestSession.make(keychain: keychain)
        first.syncDevices(through: InMemoryEntrySync(relay: relay))
        await first.load()
        try await first.createIdentity(displayName: "Griff")
        let me = try #require(first.enrolment?.device.id)
        await first.setDeviceName("The one in my pocket", for: me)

        let sibling = TestSession.make(keychain: keychain)
        sibling.syncDevices(through: InMemoryEntrySync(relay: relay))
        await sibling.load()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, sibling.deviceName(me) == nil {
            await first.refreshDeviceSync()
            await sibling.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }

        #expect(
            sibling.deviceName(me) == "The one in my pocket",
            """
            A name did not reach the member's own other device. The list has to read the same on \
            every device they own, or removing the right one is a guess on all but one of them.
            """)

        let stranger = TestSession.make(keychain: InMemoryKeychainStore())
        await stranger.load()
        try await stranger.createIdentity(displayName: "Outie")
        #expect(
            stranger.deviceName(me) == nil,
            "somebody else could read what this member calls their own devices")
    }
}

@Suite("Cutting off several devices at once", .serialized)
@MainActor
struct RemovingSeveralDevicesTests {
    private func sessionWithSpareDevices(_ count: Int) async throws -> (
        session: AppSession, room: RoomID, spares: [DeviceID]
    ) {
        let clock = TestClock(now: TestSession.now)
        let session = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        await session.load()
        try await session.createIdentity(displayName: "Griff")
        let room = try await session.createRoom(named: "Kitchen")
        let identity = try #require(session.enrolment?.identity)

        var spares: [DeviceID] = []
        for _ in 0..<count {
            clock.advance(by: 3600)
            let keys = DeviceKeys.generate()
            try session.replica.admit(
                DeviceCertificate.issue(
                    for: keys.publicKey, by: identity, at: clock.now))
            spares.append(DeviceID(publicKey: keys.publicKey))
        }
        #expect(
            spares.allSatisfy { id in session.devices.contains { $0.id == id } },
            "the fixture did not get every spare device onto the list")
        return (session, room, spares)
    }

    @Test("One removal of many turns each room's key once")
    func oneRemovalTurnsEachKeyOnce() async throws {
        let (session, room, spares) = try await sessionWithSpareDevices(3)
        let before = session.epochsHeld(in: room)

        try await session.revoke(spares)

        #expect(
            session.epochsHeld(in: room) == before + 1,
            """
            Removing three devices turned the room's key three times. Every turn is a burst of \
            rewrapping for everybody in the room, and one removal is one event.
            """)
        for spare in spares {
            #expect(
                session.devices.first { $0.id == spare }?.isActive == false,
                "a device in the batch was left able to read what is said next")
        }
    }

    @Test("This device is never in the batch, and nothing goes if it is named")
    func thisDeviceIsNeverInTheBatch() async throws {
        let (session, room, spares) = try await sessionWithSpareDevices(2)
        let me = try #require(session.enrolment?.device.id)
        let before = session.epochsHeld(in: room)

        await #expect(throws: AppSessionError.cannotRevokeThisDevice) {
            try await session.revoke(spares + [me])
        }
        #expect(
            session.devices.first { $0.id == spares[0] }?.isActive == true,
            """
            A batch containing this device cut off the others on the way to refusing. A removal \
            that cannot be completed has to change nothing, or the member is left with a key turn \
            and an error and no idea which devices went.
            """)
        #expect(session.epochsHeld(in: room) == before, "a refused removal still turned the key")
    }

    @Test("Removing nobody does nothing at all")
    func removingNobodyDoesNothing() async throws {
        let (session, room, _) = try await sessionWithSpareDevices(1)
        let before = session.epochsHeld(in: room)
        try await session.revoke([])
        #expect(session.epochsHeld(in: room) == before, "an empty removal turned every room's key")
    }
}
