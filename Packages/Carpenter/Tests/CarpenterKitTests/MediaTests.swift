@testable import CarpenterApp
@testable import CarpenterKit
@testable import CarpenterUI
import CarpenterKitTesting
import CarpenterMedia
import CoreGraphics
import Foundation
import Testing

@Suite("Sealing an attachment")
struct SealedAttachmentTests {
    private let bytes = Data((0..<5_000).map { UInt8($0 % 251) })

    @Test("What was sealed is what opens")
    func roundTrip() throws {
        let (reference, ciphertext) = try SealedAttachment.seal(bytes)
        #expect(ciphertext != bytes, "the bytes went out in the clear")
        #expect(reference.byteCount == ciphertext.count)
        #expect(reference.key.count == 32)
        #expect(SealedAttachment.matches(ciphertext, reference))
        #expect(try SealedAttachment.open(ciphertext, with: reference) == bytes)
    }

    @Test("A byte out of place fails the digest, before any key is used")
    func tamperingFailsTheDigest() throws {
        let (reference, ciphertext) = try SealedAttachment.seal(bytes)
        var tampered = ciphertext
        tampered[tampered.count / 2] ^= 0x01
        #expect(!SealedAttachment.matches(tampered, reference))
        #expect(throws: AttachmentError.digestMismatch) {
            try SealedAttachment.open(tampered, with: reference)
        }
        #expect(throws: AttachmentError.digestMismatch) {
            try SealedAttachment.open(ciphertext.prefix(100), with: reference)
        }
    }

    @Test("The right bytes under the wrong key will not open")
    func wrongKeyFails() throws {
        let (reference, ciphertext) = try SealedAttachment.seal(bytes)
        let other = AttachmentReference(
            id: reference.id, key: Data(repeating: 7, count: 32), digest: reference.digest,
            byteCount: reference.byteCount)
        #expect(throws: AttachmentError.openFailed) {
            try SealedAttachment.open(ciphertext, with: other)
        }
    }

    @Test("Ciphertext cannot be lifted under another identifier")
    func boundToItsIdentifier() throws {
        let (reference, ciphertext) = try SealedAttachment.seal(bytes)
        let lifted = AttachmentReference(
            id: AttachmentID(), key: reference.key, digest: reference.digest,
            byteCount: reference.byteCount)
        #expect(throws: AttachmentError.openFailed) {
            try SealedAttachment.open(ciphertext, with: lifted)
        }
    }

    @Test("Nothing larger than the ceiling is sealed, and the ceiling is per kind")
    func tooLargeIsRefused() throws {
        let huge = Data(count: SealedAttachment.maximumPlaintextBytes(for: .image) + 1)
        #expect(throws: AttachmentError.tooLarge) { try SealedAttachment.seal(huge, kind: .image) }
        _ = try SealedAttachment.seal(huge, kind: .video)
        let hugeClip = Data(count: SealedAttachment.maximumPlaintextBytes(for: .video) + 1)
        #expect(throws: AttachmentError.tooLarge) { try SealedAttachment.seal(hugeClip, kind: .video) }
    }

    @Test("The wire mapping carries everything an attachment record needs")
    func wireRoundTrip() {
        let outgoing = OutgoingAttachment(
            id: AttachmentID(), ciphertext: bytes,
            recipients: [RecipientTag(rawValue: Data([1])), RecipientTag(rawValue: Data([2]))])
        let fields = AttachmentWire.fields(of: outgoing)
        let back = AttachmentWire.attachment(from: fields)
        #expect(back?.id == outgoing.id)
        #expect(back?.ciphertext == bytes)
        if case .dataList(let tags)? = fields[AttachmentWire.outstanding] {
            #expect(Set(tags) == Set(outgoing.recipients.map(\.rawValue)))
        } else {
            Issue.record("the routing list was not written")
        }
    }
}

@MainActor
@Suite("Sending a photo", .serialized)
struct SendingPhotoTests {
    static func photo(caption: String? = nil, preview: Data? = Data(repeating: 0xAB, count: 900)) -> PreparedMedia {
        PreparedMedia(
            kind: .image, width: 1600, height: 1200,
            bytes: Data((0..<20_000).map { UInt8($0 % 253) }), preview: preview, caption: caption)
    }

    private func joined(aliceStore: MemoryMediaStore = MemoryMediaStore()) async throws -> (
        alice: AppSession, bob: AppSession, room: RoomID, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make(media: aliceStore)
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Darkroom")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox, media: mailbox)
            try await bob.sync(through: mailbox, media: mailbox)
        }
        return (alice, bob, room, mailbox)
    }

    @Test("A photo becomes a message with a picture and no words")
    func aPhotoIsAMessage() async throws {
        let (alice, _, room, mailbox) = try await joined()

        try await alice.send(Self.photo(), to: room, through: mailbox)

        let message = try #require(alice.messages(in: room).last)
        let media = try #require(message.media, "the picture was dropped between the fold and the screen")
        #expect(media.width == 1600 && media.height == 1200)
        #expect(media.preview?.count == 900)
        #expect(message.body.isEmpty, "a photo sent alone has no words")
        #expect(message.preview == MediaBody.line(for: .image), "where only text fits, the photo says so")
        #expect(message.isMine, "this is the sender's own path, the one the delivery-mark rebuild runs over")
        #expect(await mailbox.uploadCount == 1)
        #expect(await mailbox.storedAttachmentCount == 1)
        #expect(await alice.holdsAttachment(media.id), "the sender's own copy was not kept")
        #expect(alice.rooms.first?.lastMessage == MediaBody.line(for: .image))
    }

    @Test("A clip is a message with a length, and says so where only words fit")
    func aClipIsAMessage() async throws {
        let (alice, _, room, mailbox) = try await joined()
        let clip = PreparedMedia(
            kind: .video, width: 960, height: 540, bytes: Data(repeating: 3, count: 50_000),
            preview: Data(repeating: 4, count: 500), duration: 12)

        try await alice.send(clip, to: room, through: mailbox)

        let message = try #require(alice.messages(in: room).last)
        let media = try #require(message.media)
        #expect(media.kind == .video)
        #expect(media.duration == 12)
        #expect(message.preview == MediaBody.line(for: .video))
        #expect(alice.rooms.first?.lastMessage == "🎬 Video")
    }

    @Test("A caption is the message's words, and the rooms list says both")
    func captionIsTheBody() async throws {
        let (alice, _, room, mailbox) = try await joined()
        try await alice.send(Self.photo(caption: "the darkroom"), to: room, through: mailbox)
        let message = try #require(alice.messages(in: room).last)
        #expect(message.body == "the darkroom")
        #expect(message.media != nil)
        #expect(alice.rooms.first?.lastMessage == "📷 the darkroom")
    }

    @Test("An upload that fails sends nothing and keeps nothing")
    func uploadFailureLeavesNothing() async throws {
        let store = MemoryMediaStore()
        let (alice, _, room, mailbox) = try await joined(aliceStore: store)
        await mailbox.failNextWrite(with: .unavailable)
        let before = alice.messages(in: room).count

        await #expect(throws: MailboxError.unavailable) {
            try await alice.send(Self.photo(), to: room, through: mailbox)
        }

        #expect(alice.messages(in: room).count == before, "an entry was written for a photo nobody can fetch")
        #expect(await mailbox.storedAttachmentCount == 0)
        #expect(await store.count == 0, "the local copy of a failed send was kept")
    }

    @Test("A preview over the cap is refused before anything is uploaded")
    func oversizedPreviewIsRefused() async throws {
        let (alice, _, room, mailbox) = try await joined()
        let big = Self.photo(preview: Data(count: MediaBody.previewByteCap + 1))
        await #expect(throws: AttachmentError.previewTooLarge) {
            try await alice.send(big, to: room, through: mailbox)
        }
        #expect(await mailbox.uploadCount == 0)
    }

    @Test("A photo crosses to the other side, is checked, kept, acknowledged and opens")
    func aPhotoCrosses() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        let photo = Self.photo()
        try await alice.send(photo, to: room, through: mailbox)
        try await alice.sync(through: mailbox, media: mailbox)

        try await bob.sync(through: mailbox, media: mailbox)

        let theirs = try #require(bob.messages(in: room).last)
        let media = try #require(theirs.media)
        #expect(!theirs.isMine)
        #expect(await bob.holdsAttachment(media.id), "the round did not fetch the photo the entry named")
        #expect(await mailbox.downloadCount == 1)
        #expect(await mailbox.storedAttachmentCount == 0, "the attachment was not acknowledged")
        let opened = try await bob.attachmentData(for: media, sentBy: theirs.author.id, through: mailbox)
        #expect(opened == photo.bytes)
        #expect(await mailbox.downloadCount == 1, "opening a held photo fetched it again")
    }

    @Test("A late arrival finds the entry and not the bytes, and is told")
    func lateArrivalIsToldItIsGone() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        try await alice.send(Self.photo(), to: room, through: mailbox)
        try await alice.sync(through: mailbox, media: mailbox)
        let sent = try #require(alice.messages(in: room).last?.media)
        await mailbox.forget(attachment: sent.id)

        try await bob.sync(through: mailbox, media: mailbox)

        let theirs = try #require(bob.messages(in: room).last)
        #expect(theirs.media != nil, "the entry itself still arrives")
        let opened = try await bob.attachmentData(for: sent, sentBy: theirs.author.id, through: mailbox)
        #expect(opened == nil, "nil is the answer, not an error and not a retry")
    }

    @Test("Withdrawing a photo takes the picture back like the words")
    func withdrawing() async throws {
        let (alice, _, room, mailbox) = try await joined()
        try await alice.send(Self.photo(), to: room, through: mailbox)
        let message = try #require(alice.messages(in: room).last)

        try await alice.withdraw(message.id)

        let after = try #require(alice.messages(in: room).last)
        #expect(after.isWithdrawn)
        #expect(after.media == nil, "a withdrawn photo still offered its picture")
    }

    @Test("An edit cannot turn a photo into words")
    func editsDoNotTouchPhotos() async throws {
        let (alice, _, room, mailbox) = try await joined()
        try await alice.send(Self.photo(), to: room, through: mailbox)
        let message = try #require(alice.messages(in: room).last)

        try await alice.edit(message.id, to: "actually a sentence")

        let after = try #require(alice.messages(in: room).last)
        #expect(after.media != nil, "the edit replaced the picture")
        #expect(after.body.isEmpty)
        #expect(!after.isEdited)
    }

    @Test("A read-only round fetches no photos")
    func readOnlyRoundLeavesPhotosAlone() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        try await alice.send(Self.photo(), to: room, through: mailbox)
        try await alice.sync(through: mailbox, media: mailbox)
        let writes = await mailbox.serverWrites

        try await bob.sync(through: mailbox, media: mailbox, mode: .readOnly)

        #expect(await mailbox.downloadCount == 0)
        #expect(await mailbox.serverWrites == writes, "a read-only round wrote to the server")
        #expect(bob.messages(in: room).last?.media != nil, "the entry still arrived")
    }

    @Test("An upload no entry names is swept on the next launch; one an entry names is kept")
    func orphansAreSwept() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "carpenter-sweep-\(UUID().uuidString)")
        let alice = TestSession.make(keychain: keychain, at: directory)
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Darkroom")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox, media: mailbox)
            try await bob.sync(through: mailbox, media: mailbox)
        }

        try await alice.send(Self.photo(), to: room, through: mailbox)
        let named = try #require(alice.messages(in: room).last?.media?.id)
        let orphan = AttachmentID()
        try await mailbox.upload(OutgoingAttachment(id: orphan, ciphertext: Data([1, 2, 3]), recipients: []))
        #expect(await mailbox.storedAttachmentCount == 2)

        let relaunched = TestSession.make(keychain: keychain, at: directory)
        await relaunched.load()
        try await relaunched.sync(through: mailbox, media: mailbox)
        #expect(
            await mailbox.attachmentDeleteCount == 0,
            """
            The sweep deleted an upload made seconds ago. The hour exists so it cannot race an \
            upload whose entry has not been integrated yet, and the fake ignored it until \
            2026-09-13 — which is how a new reader came to wipe who still owed a photo.
            """)

        clock.advance(by: MailboxRules.sweepAge + 60)
        let sweeping = TestSession.make(keychain: keychain, at: directory)
        await sweeping.load()
        try await sweeping.sync(through: mailbox, media: mailbox)

        let waiting = try await mailbox.pendingAttachments()
        #expect(waiting[orphan] == nil, "the orphan survived the sweep")
        #expect(waiting[named] != nil, "the sweep deleted a photo an entry names")
        #expect(await mailbox.attachmentDeleteCount == 1)

        try await sweeping.sync(through: mailbox, media: mailbox)
        #expect(await mailbox.attachmentDeleteCount == 1, "the sweep ran twice in one launch")
    }
}

@MainActor
@Suite("Blocking", .serialized)
struct BlockingTests {
    private func joined() async throws -> (
        alice: AppSession, bob: AppSession, room: RoomID, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Darkroom")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox, media: mailbox)
            try await bob.sync(through: mailbox, media: mailbox)
        }
        return (alice, bob, room, mailbox)
    }

    @Test("A blocked person's messages are not drawn, not unread, and their photos not fetched")
    func blockingIsLocalAndImmediate() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        try await alice.send("before", to: room)
        try await alice.sync(through: mailbox, media: mailbox)
        try await bob.sync(through: mailbox, media: mailbox)
        try await bob.sync(through: mailbox, media: mailbox)
        #expect(bob.messages(in: room).contains { $0.body == "before" })

        await bob.block(aliceID)

        #expect(bob.isBlocked(aliceID))
        #expect(bob.blockedPeople.map(\.id) == [aliceID])
        #expect(!bob.messages(in: room).contains { $0.author.id == aliceID }, "still drawn after the block")
        #expect(!bob.transcript(in: room).contains { $0.message?.author.id == aliceID })
        #expect(bob.rooms.first?.hasUnread == false, "a blocked person's message counted as unread")
        #expect(bob.latestIncomingMessage() == nil, "the banner path still saw the blocked person")

        let packets = await mailbox.writeCount
        try await bob.sync(through: mailbox, media: mailbox)
        #expect(await mailbox.writeCount == packets, "blocking wrote a packet")

        try await alice.send(SendingPhotoTests.photo(), to: room, through: mailbox)
        try await alice.sync(through: mailbox, media: mailbox)
        try await bob.sync(through: mailbox, media: mailbox)
        #expect(await mailbox.downloadCount == 0, "a blocked person's photo was fetched")
        let theirs = try #require(alice.messages(in: room).last?.media)
        #expect(try await bob.attachmentData(for: theirs, sentBy: aliceID, through: mailbox) == nil)
    }

    @Test("Nothing said while blocked is lost; unblocking and a round bring it back")
    func unblockingShowsWhatWasHeld() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        await bob.block(aliceID)
        try await alice.send("while blocked", to: room)
        try await alice.sync(through: mailbox, media: mailbox)
        try await bob.sync(through: mailbox, media: mailbox)
        #expect(!bob.messages(in: room).contains { $0.body == "while blocked" })

        await bob.unblock(aliceID)
        #expect(bob.blockedPeople.isEmpty)

        // Since 2026-09-14 a block is not answering rather than not drawing, so the entry was never
        // collected and cannot appear without a round. What matters is that it was not *lost*: the
        // sender never had an acknowledgement, so the packet is still on offer and comes back.
        try await bob.sync(through: mailbox, media: mailbox)

        #expect(
            bob.messages(in: room).contains { $0.body == "while blocked" },
            """
            Something said while this member had the sender blocked did not come back after they \
            unblocked them and synced. Blocking must cost the sender delivery, never cost this \
            member the words when they change their mind.
            """)
    }

    // MARK: What a block costs the person blocked — ruled by Griff, 2026-09-14

    @Test("A blocked person's packets stop being collected, so their app never says collected")
    func aBlockedPersonsPacketsAreNotAnswered() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        await bob.block(aliceID)

        try await alice.send("does this land", to: room)
        try await alice.sync(through: mailbox, media: mailbox)
        for _ in 0..<4 { try await bob.sync(through: mailbox, media: mailbox) }

        let waiting = try await mailbox.pendingDeliveries()
        #expect(
            !waiting.isEmpty,
            """
            The blocked sender's packet was acknowledged. Blocking is meant to be noticed the way \
            it is noticed in every other messenger — by messages that stop being delivered — and \
            the app never says why. Silence is not answering, not merely not drawing: an \
            acknowledgement would tell their app *collected*, and then *shown*.
            """)
    }

    @Test("A blocked person stops being handed this member's future room keys")
    func aBlockedPersonIsHandedNoKeys() async throws {
        let (alice, bob, _, mailbox) = try await joined()
        let bobID = try #require(bob.enrolment?.identity.id)
        await alice.block(bobID)

        let second = try await alice.createRoom(named: "After the block")
        try await alice.sync(through: mailbox, media: mailbox)
        try await alice.send("not for you", to: second)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox, media: mailbox)
            try await bob.sync(through: mailbox, media: mailbox)
        }

        #expect(
            !bob.rooms.contains { $0.id == second },
            "somebody this member blocked was let into a room made after the block")
    }

    @Test("A blocked reader is dropped from the Outpost audience")
    func aBlockedReaderLosesTheOutpost() async throws {
        let (alice, bob, _, mailbox) = try await joined()
        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox, media: mailbox)
            try await bob.sync(through: mailbox, media: mailbox)
        }
        #expect(alice.outpostReaders().contains(bobID), "precondition: they could read it")

        await alice.block(bobID)

        #expect(
            !alice.outpostReaders().contains(bobID),
            """
            A blocked person is still in this member's Outpost audience. A wall has one owner and \
            nobody else to hand its key over, so this is the one place where blocking genuinely \
            ends somebody's access rather than only this device's drawing of them.
            """)
    }

    @Test("Unblocking puts them back in the audience and back on the round")
    func unblockingRestoresReach() async throws {
        let (alice, bob, _, mailbox) = try await joined()
        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox, media: mailbox)
            try await bob.sync(through: mailbox, media: mailbox)
        }

        await alice.block(bobID)
        #expect(!alice.outpostReaders().contains(bobID))

        await alice.unblock(bobID)
        #expect(
            alice.outpostReaders().contains(bobID),
            "unblocking did not put them back in the audience, so a block is a one-way door")
    }

    @Test("A block follows the member: a later stamp wins the merge either way")
    func blocksMerge() {
        let person = ParticipantID(rawValue: WideID.of([4]))
        let device = DeviceID(rawValue: WideID.of([1]))
        let earlier = OrganisationStamp(at: Date(timeIntervalSince1970: 100), device: device)
        let later = OrganisationStamp(at: Date(timeIntervalSince1970: 200), device: device)

        var phone = MemberPreferences()
        phone.setBlocked(true, person, stamp: earlier)
        var tablet = MemberPreferences()
        tablet.setBlocked(false, person, stamp: later)

        #expect(!phone.merged(with: tablet).isBlocked(person))
        #expect(!tablet.merged(with: phone).isBlocked(person))
    }

    @Test("Nobody can block themselves")
    func selfIsNeverBlocked() async throws {
        let (alice, _, _, _) = try await joined()
        let me = try #require(alice.enrolment?.identity.id)
        await alice.block(me)
        #expect(!alice.isBlocked(me))
    }

    @Test("The deny list hides a listed sender and the switch restores them")
    func denyListSwitch() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let aliceID = try #require(alice.enrolment?.identity.id)
        let bob = TestSession.make(
            denyList: DenyList(version: 1, updated: "today", fingerprints: [DenyList.fingerprint(of: aliceID)]))
        await bob.load()
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Darkroom")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox, media: mailbox)
            try await bob.sync(through: mailbox, media: mailbox)
        }
        try await alice.send("hello", to: room)
        try await alice.sync(through: mailbox, media: mailbox)
        try await bob.sync(through: mailbox, media: mailbox)

        #expect(bob.isDenyListed(aliceID))
        #expect(!bob.messages(in: room).contains { $0.body == "hello" }, "a listed sender was drawn")
        #expect(bob.rooms.first?.hasUnread != true, "a listed sender's message counted as unread")

        bob.enforcesDenyList = false
        #expect(!bob.isDenyListed(aliceID))

        // As with a block, a listed sender is not answered, so their words were never collected and
        // the switch alone cannot show them. A round after the switch must.
        for _ in 0..<4 {
            try await alice.sync(through: mailbox, media: mailbox)
            try await bob.sync(through: mailbox, media: mailbox)
        }
        #expect(bob.messages(in: room).contains { $0.body == "hello" }, "the switch did not restore them")
    }
}

@MainActor
@Suite("Loading a photo for the screen", .serialized)
struct MediaLoaderTests {
    static let onePixelJPEG = Data(base64Encoded:
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFAEBAAAAAAAAAAAAAAAAAAAAAP/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhEDEQA/AKwAB//Z")!

    private static let attachment = MediaAttachment(
        reference: AttachmentReference(
            id: AttachmentID(), key: Data(repeating: 1, count: 32),
            digest: Data(repeating: 2, count: 32), byteCount: 1),
        kind: .image, width: 1, height: 1, preview: nil)
    private static let author = ParticipantID(rawValue: WideID.of([3]))

    private func settled(_ loader: MediaLoader) async -> MediaLoadState {
        var state = loader.state(of: Self.attachment, sentBy: Self.author)
        for _ in 0..<200 where state == .loading {
            try? await Task.sleep(for: .milliseconds(10))
            state = loader.state(of: Self.attachment, sentBy: Self.author)
        }
        return state
    }

    @Test("A photo the screen flags arrives as sensitive")
    func flaggedIsSensitive() async throws {
        let screen = FakeMediaScreen()
        await screen.flag(Self.onePixelJPEG)
        let loader = MediaLoader(source: { _, _ in Self.onePixelJPEG }, screen: screen, defaults: UserDefaults(suiteName: "media-tests-\(UUID())")!)
        guard case .loaded(let loaded) = await settled(loader) else {
            Issue.record("did not load")
            return
        }
        #expect(loaded.verdict == .sensitive)
    }

    @Test("A photo the screen clears arrives as clear")
    func clearedIsClear() async throws {
        let loader = MediaLoader(source: { _, _ in Self.onePixelJPEG }, screen: FakeMediaScreen(), defaults: UserDefaults(suiteName: "media-tests-\(UUID())")!)
        guard case .loaded(let loaded) = await settled(loader) else {
            Issue.record("did not load")
            return
        }
        #expect(loaded.verdict == .clear)
    }

    @Test("With screening off in the system, the answer is not-screened — never clear")
    func offInSystemIsNotScreened() async throws {
        let loader = MediaLoader(
            source: { _, _ in Self.onePixelJPEG },
            screen: FakeMediaScreen(availability: .offInSystemSettings),
            defaults: UserDefaults(suiteName: "media-tests-\(UUID())")!)
        guard case .loaded(let loaded) = await settled(loader) else {
            Issue.record("did not load")
            return
        }
        #expect(loaded.verdict == .notScreened)
    }

    @Test("A screen that refuses to look is not-screened either")
    func refusalIsNotScreened() async throws {
        let screen = FakeMediaScreen()
        await screen.setRefuses(true)
        let loader = MediaLoader(source: { _, _ in Self.onePixelJPEG }, screen: screen, defaults: UserDefaults(suiteName: "media-tests-\(UUID())")!)
        guard case .loaded(let loaded) = await settled(loader) else {
            Issue.record("did not load")
            return
        }
        #expect(loaded.verdict == .notScreened)
    }

    @Test("No bytes anywhere is gone; a fetch that failed is failed")
    func goneAndFailed() async throws {
        struct Down: Error {}
        let gone = MediaLoader(source: { _, _ in nil }, screen: nil, defaults: UserDefaults(suiteName: "media-tests-\(UUID())")!)
        #expect(await settled(gone) == .gone)
        let failed = MediaLoader(source: { _, _ in throw Down() }, screen: nil, defaults: UserDefaults(suiteName: "media-tests-\(UUID())")!)
        guard case .failed = await settled(failed) else {
            Issue.record("a thrown fetch did not read as failed")
            return
        }
    }

    @Test("A clip loads as a playable file with a poster, and is screened as a clip")
    func aClipLoads() async throws {
        let original = try await TestVideo.make(seconds: 1, size: CGSize(width: 64, height: 64), fps: 1, tagged: false)
        defer { try? FileManager.default.removeItem(at: original) }
        let prepared = try await VideoPreparer.prepare(original)
        let attachment = MediaAttachment(
            reference: AttachmentReference(
                id: AttachmentID(), key: Data(repeating: 1, count: 32),
                digest: Data(repeating: 2, count: 32), byteCount: prepared.bytes.count),
            kind: .video, width: prepared.width, height: prepared.height, preview: prepared.preview,
            duration: prepared.duration)
        let screen = FakeMediaScreen()
        await screen.flagVideo(named: "\(attachment.id.rawValue.uuidString).mp4")
        let loader = MediaLoader(
            source: { _, _ in prepared.bytes }, screen: screen,
            defaults: UserDefaults(suiteName: "media-tests-\(UUID())")!)

        var state = loader.state(of: attachment, sentBy: Self.author)
        for _ in 0..<400 where state == .loading {
            try? await Task.sleep(for: .milliseconds(10))
            state = loader.state(of: attachment, sentBy: Self.author)
        }
        guard case .loaded(let loaded) = state else {
            Issue.record("did not load: \(state)")
            return
        }
        let url = try #require(loaded.video, "a clip loaded with nothing to play")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.path.hasPrefix(MediaLoader.playingDirectory.path))
        #expect(loaded.image.cgImage.width > 0, "no poster frame")
        #expect(loaded.verdict == .sensitive, "the clip was not screened as a clip")
        #expect(await screen.looks == 1)
    }

    @Test("Revealing is remembered on this device")
    func revealIsRemembered() {
        let defaults = UserDefaults(suiteName: "media-tests-\(UUID())")!
        let id = AttachmentID()
        let loader = MediaLoader(source: { _, _ in nil }, screen: nil, defaults: defaults)
        #expect(!loader.isRevealed(id))
        loader.reveal(id)
        #expect(loader.isRevealed(id))
        #expect(MediaLoader(source: { _, _ in nil }, screen: nil, defaults: defaults).isRevealed(id))
    }
}
