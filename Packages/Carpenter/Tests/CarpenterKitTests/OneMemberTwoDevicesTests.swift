import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@Suite("A member with two devices", .serialized)
@MainActor
struct OneMemberTwoDevicesTests {
    @Test("A message from somebody else reaches both of the member's devices")
    func bothDevicesGetTheMessage() async throws {
        let mailbox = InMemoryMailbox()
        let relay = InMemoryEntrySync.Relay()
        let keychain = InMemoryKeychainStore()

        let phone = TestSession.make(keychain: keychain)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        let friend = TestSession.make()
        for session in [phone, friend] { await session.load() }
        try await phone.createIdentity(displayName: "Griff")
        try await friend.createIdentity(displayName: "Outie")

        let room = try await phone.createRoom(named: "Kitchen")
        let invite = try await phone.invite(joinerCode: friend.identityCode(), joining: room, mailbox: nil)
        try await friend.redeem(inviteCode: try invite.encoded())
        try await phone.sync(through: mailbox)
        try await friend.accept(invite.attestation, from: try #require(phone.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [phone, friend] { try await session.sync(through: mailbox) }
        }

        try await keychain.remove(IdentityStore.deviceKey)
        let tablet = TestSession.make(keychain: keychain)
        tablet.syncDevices(through: InMemoryEntrySync(relay: relay))
        await tablet.load()
        await tablet.settleDeviceSync { tablet.rooms.contains { $0.id == room } }
        for _ in 0..<4 {
            await phone.settleDeviceSync()
            await tablet.settleDeviceSync()
        }

        try await friend.send("for both of your devices", to: room)
        for _ in 0..<8 {
            for session in [friend, phone, tablet] { try await session.sync(through: mailbox) }
            await phone.settleDeviceSync()
            await tablet.settleDeviceSync()
        }

        #expect(phone.messages(in: room).contains { $0.body == "for both of your devices" })
        #expect(
            tablet.messages(in: room).contains { $0.body == "for both of your devices" },
            "the phone collected the message first and the tablet never saw it")
    }

    @Test("A room key sealed for the phone alone still reaches it when the tablet collects it")
    func aKeyForTheOtherDeviceIsPassedOn() async throws {
        let mailbox = InMemoryMailbox()
        let relay = InMemoryEntrySync.Relay()
        let keychain = InMemoryKeychainStore()

        let phone = TestSession.make(keychain: keychain)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        let friend = TestSession.make()
        let carol = TestSession.make()
        for session in [phone, friend, carol] { await session.load() }
        try await phone.createIdentity(displayName: "Griff")
        try await friend.createIdentity(displayName: "Outie")
        try await carol.createIdentity(displayName: "Carol")

        let room = try await friend.createRoom(named: "Kitchen")
        let invite = try await friend.invite(joinerCode: phone.identityCode(), joining: room, mailbox: nil)
        try await phone.redeem(inviteCode: try invite.encoded())
        try await friend.sync(through: mailbox)
        try await phone.accept(invite.attestation, from: try #require(friend.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [friend, phone] { try await session.sync(through: mailbox) }
        }

        try await keychain.remove(IdentityStore.deviceKey)
        let tablet = TestSession.make(keychain: keychain)
        tablet.syncDevices(through: InMemoryEntrySync(relay: relay))
        await tablet.load()
        await tablet.settleDeviceSync { tablet.rooms.contains { $0.id == room } }

        let second = try await friend.invite(joinerCode: carol.identityCode(), joining: room, mailbox: nil)
        try await carol.redeem(inviteCode: try second.encoded())
        try await friend.sync(through: mailbox)
        try await carol.accept(second.attestation, from: try #require(friend.enrolment?.identity.publicKeys))
        for _ in 0..<4 {
            for session in [friend, carol] { try await session.sync(through: mailbox) }
        }
        try await friend.send("under the new key", to: room)

        for _ in 0..<10 {
            for session in [friend, tablet, phone] { try await session.sync(through: mailbox) }
            await tablet.settleDeviceSync()
            await phone.settleDeviceSync()
        }

        #expect(tablet.messages(in: room).contains { $0.body == "under the new key" })
        #expect(
            phone.messages(in: room).contains { $0.body == "under the new key" },
            "the tablet took a key sealed for the phone and the phone never got it")
    }
}
