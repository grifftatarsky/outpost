@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A packet no device is tracking leaves iCloud", .serialized)
struct APacketNobodyIsTrackingTests {
    private struct Rig {
        let clock: TestClock
        let mailbox: InMemoryMailbox
        let phone: AppSession
        let friend: AppSession
        let room: RoomID
        let keychain: InMemoryKeychainStore
        let relay: InMemoryEntrySync.Relay
    }

    private func rig() async throws -> Rig {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let relay = InMemoryEntrySync.Relay()
        let keychain = InMemoryKeychainStore()
        let phone = TestSession.make(keychain: keychain, clock: clock)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        let friend = TestSession.make(clock: clock)
        for session in [phone, friend] { await session.load() }
        try await phone.createIdentity(displayName: "Griff")
        try await friend.createIdentity(displayName: "Outie")
        let room = try await phone.createRoom(named: "Kitchen")
        let invite = try await phone.invite(
            joinerCode: await friend.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await friend.redeem(inviteCode: try invite.encoded())
        for _ in 0..<6 {
            for session in [phone, friend] { try await session.sync(through: mailbox) }
        }
        try #require(phone.roster(of: room).members.count == 2, "precondition: the friend is in")
        return Rig(clock: clock, mailbox: mailbox, phone: phone, friend: friend, room: room, keychain: keychain, relay: relay)
    }

    private func written(_ text: String, in rig: Rig) async throws -> PacketID {
        try await rig.phone.send(text, to: rig.room)
        let report = try await rig.phone.sync(through: rig.mailbox)
        let entry = try #require(rig.phone.messages(in: rig.room).last { $0.body == text }).id.entry
        return try #require(report.written.first { $0.entries.contains(entry) }?.packet, "precondition: it was written")
    }

    @Test("A packet its writer lost track of is withdrawn once nobody can find it")
    func aLostPacketIsWithdrawn() async throws {
        let rig = try await rig()
        let packet = try await written("before the crash", in: rig)
        rig.phone.persisted.outstandingPackets[packet] = nil
        rig.phone.persisted.packetsWritten[packet] = nil

        rig.clock.advance(by: SyncSession.packetWaitsFor + SyncSession.tagWindow + 60)
        _ = try await written("after the crash", in: rig)
        try await rig.phone.sync(through: rig.mailbox)

        #expect(
            await rig.mailbox.everySentPacket[packet] == nil,
            "no device was tracking the packet, so it stayed in iCloud and every reader downloads it every round")
    }

    @Test("A device whose clock is days fast does not withdraw a packet somebody can still find")
    func aFastClockWithdrawsNothingFindable() async throws {
        let rig = try await rig()
        let packet = try await written("just now", in: rig)
        rig.phone.persisted.outstandingPackets[packet] = nil
        rig.phone.persisted.packetsWritten[packet] = nil

        let fast = TestClock(now: rig.clock.now.addingTimeInterval(SyncSession.packetWaitsFor * 3))
        let sibling = TestSession.make(keychain: await rig.keychain.sibling(), clock: fast)
        sibling.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await sibling.load()
        try await rig.phone.approveNewDevice(sibling)
        await sibling.settleDeviceSync { sibling.rooms.contains { $0.id == rig.room } }
        for _ in 0..<4 {
            await rig.phone.settleDeviceSync()
            await sibling.settleDeviceSync()
        }
        _ = try? await sibling.sync(through: rig.mailbox)

        #expect(
            await rig.mailbox.everySentPacket[packet] != nil,
            "a device with a wrong clock judged a fresh packet nine days old and withdrew it before the friend could collect it")
    }

    @Test("Another of the member's devices leaves a packet alone while the device that wrote it can still settle it")
    func aSiblingLeavesAPacketItsWriterStillNeeds() async throws {
        let rig = try await rig()
        let tablet = TestSession.make(keychain: await rig.keychain.sibling(), clock: rig.clock)
        tablet.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await tablet.load()
        try await rig.phone.approveNewDevice(tablet)
        await tablet.settleDeviceSync { tablet.rooms.contains { $0.id == rig.room } }
        for _ in 0..<4 {
            await rig.phone.settleDeviceSync()
            await tablet.settleDeviceSync()
        }
        try await tablet.sync(through: rig.mailbox)

        let packet = try await written("while the friend is away", in: rig)
        rig.clock.advance(by: SyncSession.packetWaitsFor + SyncSession.tagWindow / 2)
        try await tablet.sync(through: rig.mailbox)
        #expect(
            await rig.mailbox.everySentPacket[packet] != nil,
            "the tablet withdrew a packet the phone was still tracking, so the phone could not see how it ended")

        try await rig.phone.sync(through: rig.mailbox)
        #expect(await rig.mailbox.everySentPacket[packet] == nil, "the phone did not withdraw its own packet after the wait")
        #expect(
            rig.phone.messages(in: rig.room).last { $0.body == "while the friend is away" }?.delivery == .notCollected,
            "the phone found its packet gone and could not say it was never collected")
    }
}
