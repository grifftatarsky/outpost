@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Nobody but the sender clears a photo from its outbox", .serialized)
@MainActor
struct NobodyButTheSenderClearsAPhotoTests {
    @MainActor
    private struct Pair {
        let alice: AppSession
        let bob: AppSession
        let room: RoomID
        let mailbox: InMemoryMailbox
        let clock: TestClock
        let aliceMedia: MemoryMediaStore

        var bobID: ParticipantID { bob.enrolment!.identity.id }
        var aliceID: ParticipantID { alice.enrolment!.identity.id }
        var alicesPeerForBob: Peer { alice.peers().first { $0.them == bobID }! }
        var bobsPeerForAlice: Peer { bob.peers().first { $0.them == aliceID }! }
    }

    private func pair() async throws -> Pair {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let aliceMedia = MemoryMediaStore()
        let alice = TestSession.make(media: aliceMedia, clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Darkroom")
        let invite = try await alice.invite(joinerCode: await bob.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox, media: mailbox)
            try await bob.sync(through: mailbox, media: mailbox)
        }
        try #require(alice.peers().contains { $0.them == bob.enrolment?.identity.id }, "precondition: they met")
        return Pair(alice: alice, bob: bob, room: room, mailbox: mailbox, clock: clock, aliceMedia: aliceMedia)
    }

    private func sendPhoto(_ pair: Pair) async throws -> AttachmentID {
        try await pair.alice.send(SendingPhotoTests.photo(), to: pair.room, through: pair.mailbox)
        let sent = try #require(pair.alice.messages(in: pair.room).last?.media?.id)
        try await pair.alice.sync(through: pair.mailbox, media: pair.mailbox)
        try #require(await pair.mailbox.storedAttachmentIDs.contains(sent), "precondition: the photo went up")
        return sent
    }

    @Test("Collecting a photo signs for it and leaves it; the sender clears it on its next round")
    func collectingDoesNotDelete() async throws {
        let pair = try await pair()
        let sent = try await sendPhoto(pair)

        try await pair.bob.sync(through: pair.mailbox, media: pair.mailbox)
        #expect(await pair.bob.holdsAttachment(sent))
        #expect(
            await pair.mailbox.storedAttachmentIDs.contains(sent),
            "the recipient's collecting took the photo out of the sender's outbox")
        let receipts = try #require(await pair.mailbox.everyPendingAttachment[sent]?.receipts)
        #expect(receipts.count == 1, "collecting a photo left no signature on it")

        try await pair.alice.sync(through: pair.mailbox, media: pair.mailbox)
        #expect(
            !(await pair.mailbox.storedAttachmentIDs.contains(sent)),
            "the sender did not clear a photo everybody it was for has signed for")
        #expect(await pair.alice.holdsAttachment(sent), "clearing the outbox dropped the sender's own copy")
        #expect(pair.alice.persisted.attachmentsSent[sent] == nil, "a settled photo stayed in the ledger")
    }

    @Test("A photo somebody deleted from the outbox is put back, and still reaches the person owed it")
    func aDeletedPhotoIsPutBack() async throws {
        let pair = try await pair()
        let sent = try await sendPhoto(pair)

        await pair.mailbox.forget(attachment: sent)
        try await pair.alice.sync(through: pair.mailbox, media: pair.mailbox)
        #expect(
            await pair.mailbox.storedAttachmentIDs.contains(sent),
            """
            A photo deleted by somebody holding the outbox link was not put back. Anybody the \
            outbox is shared with can delete a record in it, so the sender's own round is the \
            only thing that keeps a photo there for the people still owed it.
            """)

        try await pair.bob.sync(through: pair.mailbox, media: pair.mailbox)
        let message = try #require(pair.bob.messages(in: pair.room).last { $0.media?.id == sent })
        let media = try #require(message.media)
        let opened = try await pair.bob.attachmentData(for: media, sentBy: pair.aliceID, through: pair.mailbox)
        #expect(opened == SendingPhotoTests.photo().bytes, "the photo that was put back does not open")
    }

    @Test("Emptying who a photo is for neither stops it arriving nor makes the sender think it arrived")
    func strippingTheRecipientsChangesNothing() async throws {
        let pair = try await pair()
        let sent = try await sendPhoto(pair)

        await pair.mailbox.tamper(attachment: sent) { $0[AttachmentWire.outstanding] = .dataList([]) }
        try await pair.alice.sync(through: pair.mailbox, media: pair.mailbox)
        #expect(
            await pair.mailbox.storedAttachmentIDs.contains(sent),
            "an empty recipient list on the record made the sender clear a photo nobody had collected")

        try await pair.bob.sync(through: pair.mailbox, media: pair.mailbox)
        #expect(await pair.bob.holdsAttachment(sent), "an edited recipient list kept the photo from its recipient")

        try await pair.alice.sync(through: pair.mailbox, media: pair.mailbox)
        #expect(!(await pair.mailbox.storedAttachmentIDs.contains(sent)))
    }

    @Test("Nothing but the recipient's own signature for this photo clears it")
    func onlyARealSignatureCounts() async throws {
        let pair = try await pair()
        let sent = try await sendPhoto(pair)
        let other = try await sendPhoto(pair)
        let bob = try #require(pair.bob.enrolment)
        let peer = pair.bobsPeerForAlice
        let tag = peer.incomingTag(window: SyncSession.window(at: pair.clock.now))

        let junk = SealedReceipt(tag: tag, sealed: Data(repeating: 0x5A, count: 96))
        let forAPacket = try PacketReceipt.seal(
            PacketID(rawValue: sent.rawValue), under: tag, as: bob.identity.id, by: bob.device, to: peer.secret)
        let forTheOtherPhoto = try AttachmentReceipt.seal(
            other, under: tag, as: bob.identity.id, by: bob.device, to: peer.secret)
        for receipt in [junk, forAPacket, forTheOtherPhoto] {
            try await pair.mailbox.acknowledge(
                attachment: sent, from: try #require(pair.alice.enrolment?.identity.id), with: receipt,
                in: try pair.bob.currentPairs())
        }

        try await pair.alice.sync(through: pair.mailbox, media: pair.mailbox)
        #expect(
            await pair.mailbox.storedAttachmentIDs.contains(sent),
            """
            The sender cleared a photo on the strength of a receipt that was not the recipient \
            signing for it: bytes that do not open, the recipient's signature over a packet with \
            the same number, or their signature for a different photo copied across.
            """)
        #expect(pair.alice.persisted.attachmentsSent[sent]?.collectedBy.isEmpty == true)

        let registry = try #require(pair.alice.replica.registry(for: bob.identity.id))
        let genuine = try AttachmentReceipt.seal(sent, under: tag, as: bob.identity.id, by: bob.device, to: peer.secret)
        #expect(
            AttachmentReceipt.open(genuine, for: sent, from: bob.identity.id, with: pair.alicesPeerForBob.secret, by: registry)?
                .device == bob.device.id,
            "precondition: a genuine receipt opens, so the refusals above are about the receipts")
        #expect(
            AttachmentReceipt.open(
                genuine, for: sent, from: bob.identity.id, with: pair.alicesPeerForBob.secret,
                by: DeviceRegistry(identity: bob.identity.publicKeys)) == nil,
            "a signature from a device the recipient's registry does not list as active counted")
        #expect(
            AttachmentReceipt.open(genuine, for: sent, from: pair.aliceID, with: pair.alicesPeerForBob.secret, by: registry)
                == nil,
            "a receipt counted for somebody other than the person who signed it")
    }

    @Test("After nine days the copy in iCloud goes whatever happened, and the sender keeps its own")
    func nineDaysAndItGoes() async throws {
        let pair = try await pair()
        let sent = try await sendPhoto(pair)

        pair.clock.advance(by: AppSession.attachmentKeptFor - 60)
        try await pair.alice.sync(through: pair.mailbox, media: pair.mailbox)
        #expect(await pair.mailbox.storedAttachmentIDs.contains(sent), "the photo went before its time was up")

        pair.clock.advance(by: 120)
        try await pair.alice.sync(through: pair.mailbox, media: pair.mailbox)
        #expect(
            !(await pair.mailbox.storedAttachmentIDs.contains(sent)),
            "a photo nobody collected sat in the sender's iCloud past its time")
        #expect(await pair.alice.holdsAttachment(sent), "the sender's own copy went with the outbox copy")
        #expect(pair.alice.persisted.attachmentsSent[sent] == nil)
    }

    @Test("A photo deleted after its time is up is not put back")
    func notPutBackAfterItsTime() async throws {
        let pair = try await pair()
        let sent = try await sendPhoto(pair)

        pair.clock.advance(by: AppSession.attachmentKeptFor + 60)
        await pair.mailbox.forget(attachment: sent)
        let uploads = await pair.mailbox.uploadCount
        try await pair.alice.sync(through: pair.mailbox, media: pair.mailbox)
        #expect(await pair.mailbox.uploadCount == uploads, "a photo past its time was uploaded again")
        #expect(pair.alice.persisted.attachmentsSent[sent] == nil)
    }

    @Test("The record of who a photo is for survives a relaunch")
    func theLedgerSurvivesARelaunch() async throws {
        let keychain = InMemoryKeychainStore()
        let media = MemoryMediaStore()
        let directory = TestScratch.root.appending(path: "carpenter-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let alice = TestSession.make(keychain: keychain, at: directory, media: media, clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Darkroom")
        let invite = try await alice.invite(joinerCode: await bob.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox, media: mailbox)
            try await bob.sync(through: mailbox, media: mailbox)
        }
        try await alice.send(SendingPhotoTests.photo(), to: room, through: mailbox)
        let sent = try #require(alice.messages(in: room).last?.media?.id)

        let again = TestSession.make(keychain: keychain, at: directory, media: media, clock: clock)
        await again.load()
        #expect(
            again.persisted.attachmentsSent[sent]?.people == [try #require(bob.enrolment?.identity.id)],
            "a relaunch forgot who a photo was for, so nothing would put it back if it went")
        await mailbox.forget(attachment: sent)
        try await again.sync(through: mailbox, media: mailbox)
        #expect(await mailbox.storedAttachmentIDs.contains(sent))
    }
}

@Suite("A photo and a member with two devices", .serialized)
@MainActor
struct APhotoAndTwoDevicesTests {
    @MainActor
    private struct Rig {
        let mailbox: InMemoryMailbox
        let phone: AppSession
        let tablet: AppSession
        let friend: AppSession
        let room: RoomID
        let clock: TestClock

        func round(_ times: Int = 6) async throws {
            for _ in 0..<times {
                for session in [friend, phone, tablet] { try await session.sync(through: mailbox, media: mailbox) }
                await phone.settleDeviceSync()
                await tablet.settleDeviceSync()
            }
        }
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
        let invite = try await phone.invite(joinerCode: await friend.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await friend.redeem(inviteCode: try invite.encoded())
        try await phone.sync(through: mailbox, media: mailbox)
        try await friend.accept(invite.attestation, from: try #require(phone.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [phone, friend] { try await session.sync(through: mailbox, media: mailbox) }
        }

        let tablet = TestSession.make(keychain: await keychain.sibling(), clock: clock)
        tablet.syncDevices(through: InMemoryEntrySync(relay: relay))
        await tablet.load()
        try await phone.approveNewDevice(tablet)
        await tablet.settleDeviceSync { tablet.rooms.contains { $0.id == room } }
        let rig = Rig(mailbox: mailbox, phone: phone, tablet: tablet, friend: friend, room: room, clock: clock)
        try await rig.round(4)
        let member = try #require(phone.enrolment?.identity.id)
        try #require(
            friend.replica.registry(for: member)?.activeDevices.count == 2,
            "precondition: the friend knows both of the member's devices")
        return rig
    }

    @Test("A photo is cleared once one device of the person it was for has it")
    func oneDeviceIsEnough() async throws {
        let rig = try await rig()
        try await rig.friend.send(SendingPhotoTests.photo(), to: rig.room, through: rig.mailbox)
        let sent = try #require(rig.friend.messages(in: rig.room).last?.media?.id)
        try await rig.friend.sync(through: rig.mailbox, media: rig.mailbox)
        try await rig.phone.sync(through: rig.mailbox, media: rig.mailbox)
        try #require(await rig.phone.holdsAttachment(sent), "precondition: the phone collected it")
        #expect(await rig.mailbox.storedAttachmentIDs.contains(sent), "collecting it cleared it before the sender did")

        try await rig.friend.sync(through: rig.mailbox, media: rig.mailbox)
        #expect(
            !(await rig.mailbox.storedAttachmentIDs.contains(sent)),
            "the photo stayed in iCloud waiting for the member's other device")
    }

    @Test("The sender having another device does not keep a photo in iCloud")
    func theSendersOtherDeviceKeepsNothing() async throws {
        let rig = try await rig()
        try await rig.phone.send(SendingPhotoTests.photo(), to: rig.room, through: rig.mailbox)
        let sent = try #require(rig.phone.messages(in: rig.room).last?.media?.id)
        try await rig.phone.sync(through: rig.mailbox, media: rig.mailbox)
        try await rig.friend.sync(through: rig.mailbox, media: rig.mailbox)
        try #require(await rig.friend.holdsAttachment(sent), "precondition: the friend collected it")

        try await rig.phone.sync(through: rig.mailbox, media: rig.mailbox)
        #expect(!(await rig.mailbox.storedAttachmentIDs.contains(sent)), "the photo waited for the sender's tablet")
    }
}
