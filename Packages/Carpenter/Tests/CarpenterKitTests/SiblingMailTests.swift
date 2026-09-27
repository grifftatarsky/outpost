import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@Suite("What goes to iCloud for your other devices", .serialized)
@MainActor
struct SiblingMailTests {
    private struct Devices {
        let original: AppSession
        let incoming: AppSession
        let relay: InMemoryEntrySync.Relay
        let room: RoomID
    }

    private func twoDevices() async throws -> Devices {
        let relay = InMemoryEntrySync.Relay()
        let keychain = InMemoryKeychainStore()

        let original = TestSession.make(keychain: keychain)
        original.syncDevices(through: InMemoryEntrySync(relay: relay))
        await original.load()
        try await original.createIdentity(displayName: "Griff")

        let incoming = TestSession.make(keychain: await keychain.sibling())
        incoming.syncDevices(through: InMemoryEntrySync(relay: relay))
        await incoming.load()
        try await original.approveNewDevice(incoming)

        let room = try await original.createRoom(named: "Kitchen")
        await incoming.settleDeviceSync { incoming.rooms.contains { $0.id == room } }
        return Devices(original: original, incoming: incoming, relay: relay, room: room)
    }

    private func bytesForOneSend(_ devices: Devices, _ text: String) async throws -> Int {
        let device = try #require(devices.original.enrolment?.device.id)
        await devices.original.settleDeviceSync()
        let before = await devices.relay.bytesWritten(by: device)
        try await devices.original.send(text, to: devices.room)
        await devices.original.settleDeviceSync()
        return await devices.relay.bytesWritten(by: device) - before
    }

    @Test("A message sends only what is new, not everything the device ever wrote")
    func aSendCarriesOnlyWhatIsNew() async throws {
        let devices = try await twoDevices()
        for step in 0..<3 { try await devices.original.send("early \(step)", to: devices.room) }
        let early = try await bytesForOneSend(devices, "measured early")

        for step in 0..<60 { try await devices.original.send("later \(step)", to: devices.room) }
        let late = try await bytesForOneSend(devices, "measured late")

        #expect(
            late < early * 2,
            """
            Sending one message uploaded \(late) bytes after 60 more messages, against \(early) bytes \
            before them. What goes to iCloud for this member's other devices is growing with their \
            history, so the whole history is being sent again with every message.
            """)
    }

    @Test("What your other devices have collected is deleted from iCloud")
    func collectedMailIsDeleted() async throws {
        let devices = try await twoDevices()
        let device = try #require(devices.original.enrolment?.device.id)
        for step in 0..<5 { try await devices.original.send("step \(step)", to: devices.room) }
        await devices.incoming.settleDeviceSync {
            devices.incoming.messages(in: devices.room).count == 5
        }
        for _ in 0..<4 {
            await devices.incoming.settleDeviceSync()
            await devices.original.settleDeviceSync()
        }

        let left = await devices.relay.names(from: device)
        #expect(
            left.allSatisfy { $0.isKeptForGood },
            """
            Mail your other device already collected is still in iCloud: \(left.map(\.recordName)). \
            Only this device's small state record, and its approvals and removals, should remain.
            """)
    }

    @Test("With no other device, nothing but a small state record goes to iCloud")
    func aLoneDeviceMailsNothing() async throws {
        let relay = InMemoryEntrySync.Relay()
        let alone = TestSession.make(keychain: InMemoryKeychainStore())
        alone.syncDevices(through: InMemoryEntrySync(relay: relay))
        await alone.load()
        try await alone.createIdentity(displayName: "Griff")
        let room = try await alone.createRoom(named: "Kitchen")
        for step in 0..<10 { try await alone.send("step \(step)", to: room) }
        await alone.settleDeviceSync()

        let device = try #require(alone.enrolment?.device.id)
        let left = await relay.names(from: device)
        #expect(left.filter { $0.kind == .state }.count == 1)
        #expect(left.allSatisfy { $0.isKeptForGood }, "more than the state record and the founding certificate: \(left.map(\.recordName))")
    }

    @Test("A device added later gets everything once, and the hand-over is then deleted")
    func aNewDeviceIsCaughtUpOnce() async throws {
        let relay = InMemoryEntrySync.Relay()
        let keychain = InMemoryKeychainStore()
        let original = TestSession.make(keychain: keychain)
        original.syncDevices(through: InMemoryEntrySync(relay: relay))
        await original.load()
        try await original.createIdentity(displayName: "Griff")
        let room = try await original.createRoom(named: "Kitchen")
        for step in 0..<8 { try await original.send("before the iPad \(step)", to: room) }
        await original.settleDeviceSync()

        let added = TestSession.make(keychain: await keychain.sibling())
        added.syncDevices(through: InMemoryEntrySync(relay: relay))
        await added.load()
        try await original.approveNewDevice(added)
        await added.settleDeviceSync { added.messages(in: room).count == 8 }
        for _ in 0..<4 {
            await added.settleDeviceSync()
            await original.settleDeviceSync()
        }

        #expect(added.messages(in: room).count == 8, "the new device did not get the history")
        let device = try #require(original.enrolment?.device.id)
        let left = await relay.names(from: device)
        #expect(left.allSatisfy { $0.isKeptForGood }, "the hand-over outlived its use: \(left.map(\.recordName))")
    }

    @Test("A device away for longer than mail is kept is caught up when it comes back")
    func aLongAbsenceIsCaughtUp() async throws {
        let relay = InMemoryEntrySync.Relay(announces: false)
        let keychain = InMemoryKeychainStore()
        let clock = TestClock(now: TestSession.now)
        let original = TestSession.make(keychain: keychain, clock: clock)
        original.syncDevices(through: InMemoryEntrySync(relay: relay))
        await original.load()
        try await original.createIdentity(displayName: "Griff")
        let room = try await original.createRoom(named: "Kitchen")

        let away = TestSession.make(keychain: await keychain.sibling(), clock: clock)
        away.syncDevices(through: InMemoryEntrySync(relay: relay))
        await away.load()
        try await original.approveNewDevice(away)
        for _ in 0..<6 {
            await original.refreshDeviceSync()
            await away.refreshDeviceSync()
            await original.settleDeviceSync()
            await away.settleDeviceSync()
        }
        #expect(away.rooms.contains { $0.id == room }, "precondition: both devices are in step")

        for step in 0..<3 { try await original.send("while it was away \(step)", to: room) }
        await original.settleDeviceSync()
        clock.advance(by: SiblingMail.keptFor + 60)
        try await original.send("a month later", to: room)
        await original.settleDeviceSync()

        let device = try #require(original.enrolment?.device.id)
        #expect(
            await relay.names(from: device).allSatisfy { $0.isKeptForGood },
            "mail nobody collected for a month is still in iCloud")

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, away.messages(in: room).count < 4 {
            await away.refreshDeviceSync()
            await away.settleDeviceSync()
            await original.refreshDeviceSync()
            await original.settleDeviceSync()
        }
        #expect(
            away.messages(in: room).count == 4,
            "a device that came back after its mail expired was never caught up")
    }

    @Test("Mail taken out of order is counted once every number before it has arrived")
    func cursorsAreContiguous() {
        let sibling = DeviceID(rawValue: Data(repeating: 1, count: 32))
        var mail = SiblingMail()
        mail.took(mail: 3, from: sibling)
        mail.took(mail: 1, from: sibling)
        #expect(mail.cursors == [SiblingCursor(device: sibling, mail: 1)])
        mail.took(mail: 2, from: sibling)
        #expect(mail.cursors == [SiblingCursor(device: sibling, mail: 3)])
    }

    @Test("A record's name survives the trip through CloudKit's record name")
    func recordNamesRoundTrip() {
        let writer = DeviceID(rawValue: Data(repeating: 0xAB, count: 32))
        let target = DeviceID(rawValue: Data(repeating: 0x01, count: 32))
        for kind in [SiblingRecord.Kind.state, .mail(12), .catchUp(for: target)] {
            let name = SiblingRecord.Name(writer: writer, kind: kind)
            #expect(SiblingRecord.Name(recordName: name.recordName) == name)
        }
        #expect(SiblingRecord.Name(recordName: "mail-ab-0") == nil)
        #expect(SiblingRecord.Name(recordName: "feed-") == nil)
    }
}

extension SiblingRecord.Name {
    fileprivate var isKeptForGood: Bool {
        switch kind {
        case .state, .authority: true
        case .mail, .catchUp, .request, .approval: false
        }
    }
}
