@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("A removed device cannot take a message away from its member", .serialized)
@MainActor
struct NothingIsSnatchedTests {
    private struct Rig {
        let phone: AppSession
        let stolen: AppSession
        let friend: AppSession
        let room: RoomID
        let mailbox: InMemoryMailbox
        let clock: TestClock
    }

    private func rig() async throws -> Rig {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay(announces: false)

        let phone = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        let friend = TestSession.make(clock: clock)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        for session in [phone, friend] { await session.load() }
        try await phone.createIdentity(displayName: "Griff")
        try await friend.createIdentity(displayName: "Outie")

        let room = try await phone.createRoom(named: "Kitchen")
        let invite = try await phone.invite(joinerCode: await friend.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await friend.redeem(inviteCode: try invite.encoded())
        try await phone.sync(through: mailbox)
        try await friend.accept(invite.attestation, from: try #require(phone.enrolment?.identity.publicKeys))

        let stolen = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        stolen.syncDevices(through: InMemoryEntrySync(relay: relay))
        await stolen.load()
        try await phone.approveNewDevice(stolen)
        for _ in 0..<6 {
            for session in [phone, friend, stolen] { try await session.sync(through: mailbox) }
            await phone.settleDeviceSync()
            await stolen.settleDeviceSync()
        }
        #expect(stolen.rooms.contains { $0.id == room }, "precondition: the stolen device was in the room")

        clock.advance(by: 60)
        try await phone.revoke(try #require(stolen.enrolment?.device.id))
        for _ in 0..<3 {
            for session in [phone, friend] { try await session.sync(through: mailbox) }
        }
        #expect(stolen.enrolment != nil, "precondition: the stolen device has not heard it was removed")
        return Rig(phone: phone, stolen: stolen, friend: friend, room: room, mailbox: mailbox, clock: clock)
    }

    @Test("A removed device that collects a friend's message and signs for it does not stop the member's device getting it")
    func aReceiptFromARemovedDeviceCountsForNothing() async throws {
        let rig = try await rig()
        try await rig.friend.send("for Griff", to: rig.room)
        try await rig.friend.sync(through: rig.mailbox)

        try await rig.stolen.sync(through: rig.mailbox)
        #expect(
            !rig.stolen.messages(in: rig.room).contains { $0.body == "for Griff" },
            "the removed device read a message sent after its removal")

        try await rig.friend.sync(through: rig.mailbox)
        try await rig.phone.sync(through: rig.mailbox)
        #expect(
            rig.phone.messages(in: rig.room).contains { $0.body == "for Griff" },
            "the removed device's receipt kept the message from the member's own device")
    }

    @Test("A removed device that deletes a friend's message outright gets it sent again, without the friend writing anything new")
    func aDeletedMessageComesBack() async throws {
        let rig = try await rig()
        let before = Set(await rig.mailbox.writtenPackets)
        try await rig.friend.send("for Griff", to: rig.room)
        try await rig.friend.sync(through: rig.mailbox)
        for packet in await rig.mailbox.writtenPackets where !before.contains(packet) {
            await rig.mailbox.delete(packet: packet)
        }

        try await rig.phone.sync(through: rig.mailbox)
        #expect(
            !rig.phone.messages(in: rig.room).contains { $0.body == "for Griff" },
            "precondition: the deleted packet never reached the member")

        try await rig.friend.sync(through: rig.mailbox)
        try await rig.phone.sync(through: rig.mailbox)
        #expect(
            rig.phone.messages(in: rig.room).contains { $0.body == "for Griff" },
            "a message deleted before the member's device signed for it did not come back")
    }
}
