@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("A room key counts only when a device that counted signed it")
struct SigningARoomKeyTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let member = Identity.generate()
    private let friend = Identity.generate()
    private let phone = DeviceKeys.generate()
    private let tablet = DeviceKeys.generate()
    private let friendsDevice = DeviceKeys.generate()

    private func registry() throws -> DeviceRegistry {
        var registry = DeviceRegistry(identity: member.publicKeys)
        try registry.admit(DeviceCertificate.recovered(for: phone, by: member, at: start), storedAt: start)
        try registry.admit(
            DeviceCertificate.issue(for: tablet, by: member, at: start + 10, approvedBy: phone), storedAt: start + 10)
        try registry.revoke(
            DeviceRevocation.issue(for: tablet.id, by: member, at: start + 100, from: phone), storedAt: start + 100)
        return registry
    }

    private func grant(signedBy device: DeviceKeys, to recipient: ParticipantID? = nil) throws -> EpochGrant {
        let pairwise = try PairwiseSecret.derive(mine: member, theirs: friend.publicKeys)
        return try EpochGrant.issue(
            EpochSecret.random(), at: .initial.next, in: RoomID(), link: nil, to: pairwise,
            devices: [DeviceRecipient(device: friendsDevice.id, agreementKey: friendsDevice.agreementPublicKey)]
        ).signed(by: device, from: member.id, to: recipient ?? friend.id)
    }

    @Test("A key from a device that counts is taken, and one stored after that device was removed is not")
    func removedDevicesCannotHandOutKeys() throws {
        let registry = try registry()
        #expect(try grant(signedBy: phone).isSigned(from: member.id, to: friend.id, by: registry, storedAt: start + 200))
        #expect(try grant(signedBy: tablet).isSigned(from: member.id, to: friend.id, by: registry, storedAt: start + 50))
        #expect(
            try !grant(signedBy: tablet).isSigned(from: member.id, to: friend.id, by: registry, storedAt: start + 200),
            "a removed device handed out a room key after its removal")
    }

    @Test("A key signed by a stranger, for somebody else, or altered, is not taken")
    func forgedKeysAreRefused() throws {
        let registry = try registry()
        #expect(try !grant(signedBy: DeviceKeys.generate()).isSigned(from: member.id, to: friend.id, by: registry, storedAt: start + 200))
        #expect(
            try !grant(signedBy: phone, to: Identity.generate().id)
                .isSigned(from: member.id, to: friend.id, by: registry, storedAt: start + 200),
            "a key signed for one person was taken by another")
        #expect(
            try !grant(signedBy: phone).isSigned(from: friend.id, to: friend.id, by: registry, storedAt: start + 200),
            "a key was taken as coming from somebody other than who signed it")

        let signed = try grant(signedBy: phone)
        let swapped = EpochGrant(
            room: signed.room, epoch: signed.epoch.next, link: signed.link, wrapped: signed.wrapped,
            sealedFor: signed.sealedFor)
        #expect(!swapped.isSigned(from: member.id, to: friend.id, by: registry, storedAt: start + 200))

        let pairwise = try PairwiseSecret.derive(mine: member, theirs: friend.publicKeys)
        let unsigned = try EpochGrant.issue(
            EpochSecret.random(), at: .initial, in: RoomID(), link: nil, to: pairwise,
            devices: [DeviceRecipient(device: friendsDevice.id, agreementKey: friendsDevice.agreementPublicKey)])
        #expect(!unsigned.isSigned(from: member.id, to: friend.id, by: registry, storedAt: start + 200))
    }
}

@Suite("A removed device cannot hand a friend a room key", .serialized)
@MainActor
struct ARemovedDeviceCannotHandOutKeysTests {
    @Test("A key a removed device writes for a friend after its removal is refused, and the friend keeps writing under the real one")
    func aForgedKeyIsRefusedByTheFriend() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay(announces: false)

        let phone = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        let friend = TestSession.make(clock: clock)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        for session in [phone, friend] { await session.load() }
        try await phone.createIdentity(displayName: "Griff")
        try await friend.createIdentity(displayName: "Outie")

        let stolen = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        stolen.syncDevices(through: InMemoryEntrySync(relay: relay))
        await stolen.load()
        try await phone.approveNewDevice(stolen)

        let room = try await phone.createRoom(named: "Kitchen")
        let invite = try await phone.invite(joinerCode: await friend.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await friend.redeem(inviteCode: try invite.encoded())
        try await phone.sync(through: mailbox)
        try await friend.accept(invite.attestation, from: try #require(phone.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [phone, friend] { try await session.sync(through: mailbox) }
        }
        let stolenDevice = try #require(stolen.enrolment?.device)
        let memberID = try #require(phone.enrolment?.identity.id)
        let friendID = try #require(friend.enrolment?.identity.id)

        clock.advance(by: 60)
        try await phone.revoke(stolenDevice.id)
        for _ in 0..<4 {
            for session in [phone, friend] { try await session.sync(through: mailbox) }
        }
        let before = try #require(friend.chains[room]?.highestKnownEpoch)
        #expect(
            friend.replica.registry(for: memberID)?.standing(of: stolenDevice.id)?.revokedAt != nil,
            "precondition: the friend heard of the removal")

        let pairwise = try PairwiseSecret.derive(
            mine: try #require(stolen.enrolment?.identity), theirs: try #require(friend.enrolment?.identity.publicKeys))
        let made = EpochSecret.random()
        let forged = try EpochGrant.issue(
            made, at: before.next, in: room, link: nil, to: pairwise,
            devices: phone.deviceRecipients(of: friendID)
        ).signed(by: stolenDevice, from: memberID, to: friendID)
        let toFriend = Peer(secret: pairwise, them: friendID, me: memberID)
        clock.advance(by: 60)
        try await mailbox.put(
            try SyncEngine.pack([], for: [toFriend], granting: [(to: toFriend, grant: forged)],
                window: SyncSession.window(at: clock.now)),
            to: friendID, in: Pairs(me: memberID, hints: [friendID: pairwise.pairHint]))

        for _ in 0..<3 { try await friend.sync(through: mailbox) }

        #expect(
            friend.chains[room]?.highestKnownEpoch == before,
            "a removed device handed the friend a room key and the friend took it")
        #expect((try? friend.chains[room]?.secret(for: before.next)) != made)
    }
}

@Suite("A removed device cannot pass anything to the member's other devices", .serialized)
@MainActor
struct ARemovedDeviceCannotWriteToSiblingsTests {
    @Test("A record in another device's name, or in its own after its removal, carries no room key or setting in")
    func forgedSiblingRecordsAreRefused() async throws {
        let relay = InMemoryEntrySync.Relay()
        let clock = TestClock(now: TestSession.now)
        let phone = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        await phone.load()
        try await phone.createIdentity(displayName: "Griff")
        let room = try await phone.createRoom(named: "Kitchen")

        let laptop = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        laptop.syncDevices(through: InMemoryEntrySync(relay: relay))
        await laptop.load()
        try await phone.approveNewDevice(laptop)
        let stolen = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        stolen.syncDevices(through: InMemoryEntrySync(relay: relay))
        await stolen.load()
        try await phone.approveNewDevice(stolen)
        await phone.settleDeviceSync()

        let identity = try #require(stolen.enrolment?.identity)
        let stolenKeys = try #require(stolen.enrolment?.device)
        let laptopID = try #require(laptop.enrolment?.device.id)
        let phoneKeys = try #require(phone.enrolment?.device)
        clock.advance(by: 60)
        try await phone.revoke(stolenKeys.id)
        await phone.settleDeviceSync()
        let before = try #require(phone.chains[room]?.highestKnownEpoch)

        let made = EpochSecret.random()
        var preferences = MemberPreferences()
        preferences.setDisplayName("Not Griff", stamp: OrganisationStamp(at: clock.now + 3600, device: stolenKeys.id))
        let feed = SiblingFeed(
            entries: [], certificates: [], epochs: [HeldEpoch(room: room, epoch: before.next, material: made.material)],
            member: identity.id, writtenAt: clock.now, preferences: preferences)
        let toPhone = [DeviceRecipient(device: phoneKeys.id, agreementKey: phoneKeys.agreementPublicKey)]

        let asLaptop = try SealedSiblingFeed.seal(feed, for: identity, on: laptopID, as: .mail(900), to: toPhone)
        try await relay.place(SiblingRecord.Name(writer: laptopID, kind: .mail(900)), asLaptop)
        let asItself = try SealedSiblingFeed.seal(
            feed, for: identity, on: stolenKeys.id, as: .mail(901), to: toPhone, signedBy: stolenKeys)
        try await relay.place(SiblingRecord.Name(writer: stolenKeys.id, kind: .mail(901)), asItself)
        for _ in 0..<3 {
            await phone.refreshDeviceSync()
            await phone.settleDeviceSync()
        }

        #expect(phone.chains[room]?.highestKnownEpoch == before, "a forged record gave the phone a room key")
        #expect(phone.viewer.displayName == "Griff", "a forged record changed the member's settings")

        let genuine = SiblingFeed(entries: [], certificates: [], member: identity.id, writtenAt: clock.now,
            preferences: preferences)
        let fromLaptop = try SealedSiblingFeed.seal(
            genuine, for: identity, on: laptopID, as: .mail(902), to: toPhone,
            signedBy: try #require(laptop.enrolment?.device))
        try await relay.place(SiblingRecord.Name(writer: laptopID, kind: .mail(902)), fromLaptop)
        for _ in 0..<3 {
            await phone.refreshDeviceSync()
            await phone.settleDeviceSync()
        }
        #expect(phone.viewer.displayName == "Not Griff", "the control: a record the laptop really signed was refused")
    }
}
