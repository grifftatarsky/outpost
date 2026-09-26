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

    private func rig(afterALoss: Bool = true) async throws -> Rig {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay()

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
        await restored.settleDeviceSync { !restored.rooms.isEmpty }
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

    @Test("A device removed from the device list reads nothing said afterwards")
    func aRevokedDeviceReadsNothingNew() async throws {
        let rig = try await rig(afterALoss: false)
        let stolenDevice = try #require(rig.stolen.enrolment?.device.id)
        try await rig.restored.revoke(stolenDevice)
        for _ in 0..<12 {
            for session in [rig.restored, rig.peer, rig.stolen] { try await session.sync(through: rig.mailbox) }
        }

        try await rig.peer.send("after the removal", to: rig.room)
        for _ in 0..<12 {
            for session in [rig.peer, rig.stolen, rig.restored] { try await session.sync(through: rig.mailbox) }
        }

        withKnownIssue(
            """
            New room keys are sent to the member, not to a device, so a removed device that still has \
            the identity key opens them. It checked the mailbox first here, so it read the message and \
            took the delivery, and the member's real device never got it.
            """
        ) {
            #expect(!rig.stolen.messages(in: rig.room).contains { $0.body == "after the removal" })
            #expect(rig.restored.messages(in: rig.room).contains { $0.body == "after the removal" })
        }
    }
}
