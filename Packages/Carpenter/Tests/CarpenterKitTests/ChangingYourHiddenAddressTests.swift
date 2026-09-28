@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Changing your hidden address when a device is removed", .serialized)
@MainActor
struct ChangingYourHiddenAddressTests {
    @MainActor
    private struct Rig {
        let mailbox: InMemoryMailbox
        let clock: TestClock
        let phone: AppSession
        let tablet: AppSession
        let friend: AppSession
        let room: RoomID

        var griff: ParticipantID { tablet.enrolment!.identity.id }
        var friendID: ParticipantID { friend.enrolment!.identity.id }

        func rounds(_ times: Int = 6, including sessions: [AppSession]? = nil) async throws {
            for _ in 0..<times {
                for session in sessions ?? [tablet, friend] {
                    try await session.sync(through: mailbox, media: mailbox)
                }
                await tablet.settleDeviceSync()
            }
        }
    }

    private func rig(announcing: Bool = false) async throws -> Rig {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let relay = InMemoryEntrySync.Relay(announces: announcing)
        let keychain = InMemoryKeychainStore()

        let phone = TestSession.make(keychain: keychain, clock: clock)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        let friend = TestSession.make(clock: clock)
        for session in [phone, friend] { await session.load() }
        try await phone.createIdentity(displayName: "Griff")
        try await friend.createIdentity(displayName: "Outie")

        let room = try await phone.createRoom(named: "Kitchen")
        let invite = try await phone.invite(joinerCode: await friend.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await friend.redeem(inviteCode: try invite.encoded())
        try await phone.sync(through: mailbox)
        try await friend.accept(invite.attestation, from: try #require(phone.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [phone, friend] { try await session.sync(through: mailbox) }
        }

        let tablet = TestSession.make(keychain: await keychain.sibling(), clock: clock)
        tablet.syncDevices(through: InMemoryEntrySync(relay: relay))
        await tablet.load()
        try await phone.approveNewDevice(tablet)
        let deadline = Date().addingTimeInterval(5)
        while tablet.rooms.isEmpty, Date() < deadline {
            await phone.refreshDeviceSync()
            await phone.settleDeviceSync()
            await tablet.refreshDeviceSync()
            await tablet.settleDeviceSync()
        }
        let rig = Rig(mailbox: mailbox, clock: clock, phone: phone, tablet: tablet, friend: friend, room: room)
        try await rig.rounds(6, including: [phone, tablet, friend])
        try #require(!tablet.rooms.isEmpty, "precondition: the tablet has the room")
        return rig
    }

    private func removePhone(_ rig: Rig) async throws {
        try await rig.tablet.revoke(try #require(rig.phone.enrolment?.device.id))
        try await rig.rounds(6)
    }

    private func legacy(_ session: AppSession, with person: ParticipantID) throws -> PairwiseSecret {
        try #require(session.legacySecret(with: person))
    }

    @Test("Nobody's address changes until a device is removed, so every secret is the one it always was")
    func nothingChangesWithoutARemoval() async throws {
        let rig = try await rig()
        #expect(rig.tablet.addressBook.ownCurrent == nil)
        #expect(rig.tablet.pairwiseSecret(with: rig.friendID) == (try legacy(rig.tablet, with: rig.friendID)))
        #expect(rig.friend.pairwiseSecret(with: rig.griff) == (try legacy(rig.friend, with: rig.griff)))
        #expect(rig.tablet.alternateSecrets(with: rig.friendID).isEmpty, "a member who never changed listens twice")
    }

    @Test("After a removal the contact writes to an address the removed device cannot work out or open")
    func theRemovedDeviceLosesTheAddress() async throws {
        let rig = try await rig()
        let phoneKnew = rig.phone.secrets(with: rig.friendID)
        try await removePhone(rig)

        let salt = try #require(rig.tablet.addressBook.ownCurrent, "removing a device did not change the address")
        #expect(rig.friend.addressBook.current(of: rig.griff) == salt, "the contact never took the new address")
        let now = try #require(rig.friend.pairwiseSecret(with: rig.griff))
        #expect(!phoneKnew.contains(now), "the removed device already knew the new secret")
        #expect(now == rig.tablet.pairwiseSecret(with: rig.friendID), "the two sides disagree about the new secret")

        try await rig.friend.send("after the phone was removed", to: rig.room)
        let said = try #require(rig.friend.messages(in: rig.room).last?.id.entry)
        try await rig.friend.sync(through: rig.mailbox, media: rig.mailbox)

        let session = SyncSession(mailbox: rig.mailbox, pairs: try rig.tablet.currentPairs(), clock: rig.clock)
        let asThePhone = Peer(secret: phoneKnew[0], them: rig.friendID, me: rig.griff)
        let found = try await session.collect(as: asThePhone, alternates: Array(phoneKnew.dropFirst()))
        #expect(
            !found.entries.contains { $0.hash == said },
            "a device holding the identity and every address it knew found and opened a packet written after its removal")

        try await rig.rounds(4)
        #expect(
            rig.tablet.messages(in: rig.room).contains { $0.body == "after the phone was removed" },
            "the member's real device lost the message in the change")
    }

    @Test("What the contact wrote to the old address before hearing of the new one still arrives")
    func oldAddressMailStillArrives() async throws {
        let rig = try await rig()
        try await rig.tablet.revoke(try #require(rig.phone.enrolment?.device.id))
        try await rig.friend.send("written before the news", to: rig.room)
        try await rig.friend.sync(through: rig.mailbox, media: rig.mailbox)
        #expect(
            rig.friend.addressBook.current(of: rig.griff) == nil,
            "precondition: the contact wrote before hearing of the new address")

        try await rig.rounds(6)
        #expect(rig.tablet.messages(in: rig.room).contains { $0.body == "written before the news" })
        #expect(rig.friend.addressBook.current(of: rig.griff) != nil)
    }

    @Test("What the member wrote to the new address before the contact heard of it arrives once they have")
    func newAddressMailWaitsForTheNews() async throws {
        let rig = try await rig()
        try await rig.tablet.revoke(try #require(rig.phone.enrolment?.device.id))
        try await rig.tablet.send("written at once", to: rig.room)
        try await rig.tablet.sync(through: rig.mailbox, media: rig.mailbox)
        try await rig.rounds(6)
        #expect(rig.friend.messages(in: rig.room).contains { $0.body == "written at once" })
    }

    @Test("A contact away longer than a packet waits still hears of the new address when they come back")
    func anAbsentContactStillHears() async throws {
        let rig = try await rig()
        try await rig.tablet.revoke(try #require(rig.phone.enrolment?.device.id))
        for _ in 0..<3 { try await rig.tablet.sync(through: rig.mailbox, media: rig.mailbox) }
        rig.clock.advance(by: SyncSession.tagWindow * Double(SyncSession.windowLookback + 3))
        for _ in 0..<3 { try await rig.tablet.sync(through: rig.mailbox, media: rig.mailbox) }

        try await rig.rounds(6)
        #expect(
            rig.friend.addressBook.current(of: rig.griff) == rig.tablet.addressBook.ownCurrent,
            "the announcement went stale while the contact was away and was never sent again")
        try await rig.friend.send("back after a fortnight", to: rig.room)
        try await rig.rounds(4)
        #expect(rig.tablet.messages(in: rig.room).contains { $0.body == "back after a fortnight" })
    }

    @Test("An announcement from the removed device is refused, and one it made while it counted is overtaken")
    func theRemovedDeviceCannotChooseTheAddress() async throws {
        let rig = try await rig()
        await rig.phone.rotateAddress(because: "a test: the phone changes it while it still counts")
        try await rig.rounds(4, including: [rig.phone, rig.tablet, rig.friend])
        let phones = try #require(rig.phone.addressBook.ownCurrent)
        #expect(rig.friend.addressBook.current(of: rig.griff) == phones, "precondition: a device that counts was heard")

        try await removePhone(rig)
        let tablets = try #require(rig.tablet.addressBook.ownCurrent)
        #expect(tablets != phones)
        #expect(rig.friend.addressBook.current(of: rig.griff) == tablets, "the removal's address did not win")

        await rig.phone.rotateAddress(because: "a test: the removed phone tries again")
        try? await rig.phone.sync(through: rig.mailbox, media: rig.mailbox)
        try await rig.rounds(4)
        #expect(
            rig.friend.addressBook.current(of: rig.griff) == tablets,
            "an address announced by a device after its removal replaced the member's own")
    }

    @Test("An old announcement delivered again does not take the address back")
    func noRollback() async throws {
        let rig = try await rig()
        try await removePhone(rig)
        let tablet = try #require(rig.tablet.enrolment)
        let neverSeen = AddressSalt.fresh(after: 0)
        let old = try AddressAnnouncement.make(
            neverSeen, from: rig.griff, by: tablet.device, to: rig.friendID,
            devices: rig.tablet.deviceRecipients(of: rig.friendID))

        rig.clock.advance(by: 60)
        await rig.tablet.rotateAddress(because: "a test: a second change")
        try await rig.rounds(6)
        let second = try #require(rig.tablet.addressBook.ownCurrent)
        #expect(rig.friend.addressBook.current(of: rig.griff) == second)

        let peer = try #require(rig.friend.peers().first { $0.them == rig.griff })
        let newest = try #require(rig.friend.addressBook.peers[rig.griff]?.compactMap(\.storedAt).max())
        let registry = try #require(rig.friend.replica.registry(for: rig.griff))
        try #require(
            old.open(as: try #require(rig.friend.enrolment?.device), of: rig.friendID, from: registry,
                storedAt: newest - 30) != nil,
            "precondition: the replayed announcement is one the contact would open, so only its age is refused")
        await rig.friend.takeAddresses(
            [SyncReport.ReceivedAddress(announcement: old, storedAt: newest - 30)], from: peer)
        #expect(
            rig.friend.addressBook.current(of: rig.griff) == second,
            "an announcement stored before the newest one took the address back")
    }

    @Test("Both people changing at once still hear each other")
    func bothChangeAtOnce() async throws {
        let rig = try await rig()
        await rig.friend.rotateAddress(because: "a test: the contact changes too")
        try await rig.tablet.revoke(try #require(rig.phone.enrolment?.device.id))
        try await rig.rounds(8)

        #expect(rig.friend.addressBook.current(of: rig.griff) == rig.tablet.addressBook.ownCurrent)
        #expect(rig.tablet.addressBook.current(of: rig.friendID) == rig.friend.addressBook.ownCurrent)
        #expect(rig.tablet.pairwiseSecret(with: rig.friendID) == rig.friend.pairwiseSecret(with: rig.griff))

        try await rig.friend.send("from the contact", to: rig.room)
        try await rig.tablet.send("from the member", to: rig.room)
        try await rig.rounds(4)
        #expect(rig.tablet.messages(in: rig.room).contains { $0.body == "from the contact" })
        #expect(rig.friend.messages(in: rig.room).contains { $0.body == "from the member" })
    }

    @Test("The member's other devices take the new address from the device that changed it")
    func siblingsTakeTheNewAddress() async throws {
        let rig = try await rig(announcing: true)
        await rig.tablet.rotateAddress(because: "a test: a change the phone should hear about")
        for _ in 0..<4 {
            await rig.tablet.refreshDeviceSync()
            await rig.tablet.settleDeviceSync()
            await rig.phone.refreshDeviceSync()
            await rig.phone.settleDeviceSync()
        }
        #expect(
            rig.phone.addressBook.ownCurrent == rig.tablet.addressBook.ownCurrent,
            "the member's other device never learnt the address it now has to be reached at")
    }

    @Test("The address book is kept on this device only, never where the removed device could sync it")
    func theAddressBookStaysOnTheDevice() async throws {
        let keychain = InMemoryKeychainStore()
        let session = TestSession.make(keychain: keychain)
        await session.load()
        try await session.createIdentity(displayName: "Griff")
        await session.rotateAddress(because: "a test")
        #expect(try await keychain.data(for: AddressBook.key) != nil, "precondition: the book was written")
        #expect(
            try await keychain.sibling().data(for: AddressBook.key) == nil,
            "the address book went into the keychain that reaches every device on the Apple Account")
    }

    @Test("A member who removed a device before addresses could change gets one change, not one per round")
    func oneChangeForAnOldRemoval() async throws {
        let rig = try await rig()
        try await rig.tablet.revoke(try #require(rig.phone.enrolment?.device.id))
        await rig.tablet.changeAddressBook { book in
            book = AddressBook()
            return true
        }
        #expect(rig.tablet.addressBook.ownCurrent == nil, "precondition: as if the removal came before this build")

        try await rig.rounds(3)
        let changed = try #require(rig.tablet.addressBook.ownCurrent, "an old removal never changed the address")
        try await rig.rounds(3)
        #expect(rig.tablet.addressBook.ownCurrent == changed, "the address changed again with nothing removed")
    }

    @Test("A comment sealed for a wall's owner still opens after the commenter's address changes")
    func wallCommentsStillOpen() async throws {
        let rig = try await rig()
        await rig.tablet.setOutpostConsent(.closed)
        try await removePhone(rig)
        #expect(
            rig.tablet.pairwiseSecret(with: rig.friendID) != (try legacy(rig.tablet, with: rig.friendID)),
            "precondition: the address changed")

        try await rig.tablet.appendToWall(
            of: rig.friendID, try Payload.comment(on: EntryHash(rawValue: Data(repeating: 1, count: 32)), text: "for you"))
        let comment = try #require(rig.tablet.replica.allEntries.last { $0.author == rig.griff })
        #expect(comment.hasSecondReader, "precondition: the comment was sealed a second time for the wall's owner")
        #expect(
            rig.friend.entryOpener()(comment) != nil,
            """
            The wall's owner could not open a comment sealed for them after the commenter's address \
            changed. A comment is kept in the log for good, so it has to be sealed under the secret \
            the two of them will always have, not the one that moves.
            """)
    }
}
