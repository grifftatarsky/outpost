@testable import CarpenterApp
import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("What rotating every key after a loss cuts off", .serialized)
@MainActor
struct WhatALossRotationCutsOffTests {
    private struct Rig {
        let stolen: AppSession
        let restored: AppSession
        let peer: AppSession
        let room: RoomID
        let mailbox: InMemoryMailbox
        let rotatedFrom: Int
    }

    private func rig(afterALoss: Bool = true, announcing: Bool = true) async throws -> Rig {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay(announces: announcing)

        let stolen = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        let peer = TestSession.make(clock: clock)
        stolen.syncDevices(through: InMemoryEntrySync(relay: relay))
        for session in [stolen, peer] { await session.load() }
        try await stolen.createIdentity(displayName: "Griff")
        try await peer.createIdentity(displayName: "Outie")

        let room = try await stolen.createRoom(named: "Kitchen")
        let invite = try await stolen.invite(joinerCode: peer.identityCode(), joining: room, mailbox: nil)
        try await peer.redeem(inviteCode: try invite.encoded())
        try await stolen.sync(through: mailbox)
        try await peer.accept(invite.attestation, from: try #require(stolen.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [stolen, peer] { try await session.sync(through: mailbox) }
        }
        await stolen.settleDeviceSync()
        let key = try #require(stolen.recoveryKeyText())
        let rotatedFrom = stolen.epochsHeld(in: room)

        let restored = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        restored.syncDevices(through: InMemoryEntrySync(relay: relay))
        await restored.load()
        try await restored.restore(fromRecoveryKey: key, afterALoss: afterALoss)
        let deadline = Date().addingTimeInterval(5)
        while restored.rooms.isEmpty, Date() < deadline {
            await stolen.refreshDeviceSync()
            await stolen.settleDeviceSync()
            await restored.refreshDeviceSync()
            await restored.settleDeviceSync()
        }
        for _ in 0..<12 {
            for session in [restored, peer] { try await session.sync(through: mailbox) }
        }
        return Rig(
            stolen: stolen, restored: restored, peer: peer, room: room, mailbox: mailbox,
            rotatedFrom: rotatedFrom)
    }

    @Test("The restored device reads what is said after the rotation")
    func theRestoredDeviceReads() async throws {
        let rig = try await rig()
        #expect(rig.restored.epochsHeld(in: rig.room) > rig.rotatedFrom, "the loss did not rotate the key")

        try await rig.peer.send("after the rotation", to: rig.room)
        for _ in 0..<12 {
            for session in [rig.peer, rig.restored] { try await session.sync(through: rig.mailbox) }
        }

        #expect(rig.restored.messages(in: rig.room).contains { $0.body == "after the rotation" })
    }

    @Test("A device that still holds the identity is not cut off by the rotation")
    func aDeviceHoldingTheIdentityIsNotCutOff() async throws {
        let rig = try await rig()

        try await rig.peer.send("after the rotation", to: rig.room)
        for _ in 0..<12 {
            for session in [rig.peer, rig.stolen, rig.restored] { try await session.sync(through: rig.mailbox) }
        }

        withKnownIssue(
            """
            A grant is wrapped under the pairwise secret of two identities, so any device holding the \
            identity opens it. Rotating every key after a loss cuts off nobody who kept the identity \
            key and can reach the mailbox, and whichever device fetches first takes the delivery.
            """
        ) {
            #expect(!rig.stolen.messages(in: rig.room).contains { $0.body == "after the rotation" })
        }
    }

    @Test("A device removed from the device list erases itself and reads nothing said afterwards")
    func aRevokedDeviceErasesItself() async throws {
        let rig = try await rig(afterALoss: false)
        let stolenDevice = try #require(rig.stolen.enrolment?.device.id)
        try await rig.restored.revoke(stolenDevice)
        for _ in 0..<6 {
            for session in [rig.restored, rig.peer] { try await session.sync(through: rig.mailbox) }
            try? await rig.stolen.sync(through: rig.mailbox)
            await rig.restored.settleDeviceSync()
            await rig.stolen.settleDeviceSync()
        }
        #expect(rig.stolen.state == .removed, "the removed device never noticed it was removed")

        try await rig.peer.send("after the removal", to: rig.room)
        for _ in 0..<12 {
            try await rig.peer.sync(through: rig.mailbox)
            try? await rig.stolen.sync(through: rig.mailbox)
            try await rig.restored.sync(through: rig.mailbox)
        }

        #expect(!rig.stolen.messages(in: rig.room).contains { $0.body == "after the removal" })
        #expect(rig.restored.messages(in: rig.room).contains { $0.body == "after the removal" })
    }

    @Test("A removed device that never hears it was removed still cannot open anything new")
    func aRevokedDeviceThatIsNotToldCannotRead() async throws {
        let rig = try await rig(afterALoss: false, announcing: false)
        let stolenDevice = try #require(rig.stolen.enrolment?.device.id)
        try await rig.restored.revoke(stolenDevice)
        for _ in 0..<6 {
            for session in [rig.restored, rig.peer] { try await session.sync(through: rig.mailbox) }
            await rig.restored.settleDeviceSync()
        }
        #expect(rig.stolen.state != .removed, "precondition: the removed device has not been told")

        try await rig.peer.send("after the removal", to: rig.room)
        for _ in 0..<12 {
            for session in [rig.peer, rig.stolen, rig.restored] { try await session.sync(through: rig.mailbox) }
        }

        #expect(
            !rig.stolen.messages(in: rig.room).contains { $0.body == "after the removal" },
            "a removed device that kept running read a message sent after its removal")
        withKnownIssue(
            """
            The removed device checked the mailbox first and took the delivery, so the member's real \
            device never got the message. Deliveries are acknowledged per member, not per device.
            """
        ) {
            #expect(rig.restored.messages(in: rig.room).contains { $0.body == "after the removal" })
        }
    }
}
