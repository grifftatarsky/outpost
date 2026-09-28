@testable import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("The in-memory mailbox is no easier than the real one", .serialized)
struct TheFakeIsNoEasierTests {
    private func linked(_ mailbox: InMemoryMailbox) async throws -> (toBob: Peer, asBob: Peer, alice: Pairs, bob: Pairs) {
        let (toBob, asBob) = try peers(Identity.generate(), Identity.generate())
        let (alice, bob) = try await link(toBob, asBob, through: mailbox)
        return (toBob, asBob, alice, bob)
    }

    @Test("A packet too big for a real record is refused here too")
    func aPacketTooBigIsRefused() async throws {
        let mailbox = InMemoryMailbox()
        let pair = try await linked(mailbox)
        let huge = SyncPacket(
            wraps: [pair.toBob.outgoingTag(window: 1): Data(count: 32)],
            ciphertext: Data(count: MailboxRules.recordByteCeiling + 1))

        await #expect(throws: MailboxError.self) {
            try await mailbox.put(huge, to: pair.toBob.them, in: pair.alice)
        }
        #expect(
            await mailbox.storedPacketCount == 0,
            """
            A record over the app's own ceiling was accepted. The ceiling is ours, not CloudKit's \
            — measured against a real account 2026-09-14, the server took a sixteen-megabyte record \
            without complaint — so `MailboxRules.recordByteCeiling` and \
            `SyncSession.packetByteBudget` under it are the only things keeping a round small, and \
            both mailboxes have to hold the line.
            """)
    }

    @Test("A packet within the ceiling still goes")
    func aPacketWithinTheCeilingGoes() async throws {
        let mailbox = InMemoryMailbox()
        let pair = try await linked(mailbox)
        let big = SyncPacket(
            wraps: [pair.toBob.outgoingTag(window: 1): Data(count: 32)], ciphertext: Data(count: SyncSession.packetByteBudget))

        try await mailbox.put(big, to: pair.toBob.them, in: pair.alice)
        #expect(
            await mailbox.storedPacketCount == 1,
            "a packet at the app's own budget was refused, so the budget is above the ceiling")
    }

    @Test("A copy says when it was first stored, as iCloud's creation date does, and a rewrite does not move it")
    func aCopyKeepsWhenItWasFirstStored() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let pair = try await linked(mailbox)
        let tag = pair.toBob.outgoingTag(window: 1)
        let copies = try OutgoingAttachment(
            id: AttachmentID(), ciphertext: Data(count: 16), recipients: [pair.toBob.them: tag]
        ).copies(between: { _ in pair.toBob.secret })

        try await mailbox.upload(copies, in: pair.alice)
        let first = try #require(await mailbox.storedCopies(in: pair.alice).first)
        #expect(first.recipients == [tag], "a fresh upload did not report who it is for")

        clock.advance(by: MailboxRules.sweepAge + 1)
        try await mailbox.upload(copies, in: pair.alice)
        let again = try #require(await mailbox.storedCopies(in: pair.alice).first)
        #expect(
            again.storedAt == first.storedAt,
            """
            Writing a copy again moved when it was first stored. iCloud keeps a record's creation \
            date through a rewrite, and the sweep waits on that date so it cannot race an upload \
            whose entry has not arrived yet; answering "how old" with the last write is what let a \
            new reader wipe the outstanding list of a photo posted minutes earlier.
            """)
        #expect(again.modifiedAt > first.modifiedAt)
    }

    @MainActor
    private func entries(_ text: String, into log: MemoryLogStore) async throws -> [Entry] {
        let session = AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(), log: log,
                documents: FileDocumentStore(
                    url: TestScratch.root.appending(
                        path: "carpenter-fake-\(UUID().uuidString)")),
                media: MemoryMediaStore()),
            clock: TestClock(now: TestSession.now))
        await session.load()
        try await session.createIdentity(displayName: "Griff")
        let room = try await session.createRoom(named: "Kitchen")
        try await session.send(text, to: room)
        return try await log.loadAll().entries
    }

    @Test("The in-memory log round-trips every entry through its encoding")
    @MainActor
    func theMemoryLogRoundTripsThroughEncoding() async throws {
        let log = MemoryLogStore()
        let written = try await entries("kept on disk", into: log)

        #expect(
            !written.isEmpty,
            """
            Nothing came back out of the fake log. It used to hold the struct, so anything that \
            failed to serialise passed here and failed on disk — the shape of the bug that put \
            every epoch secret into CloudKit in the clear.
            """)
        let loaded = try await log.loadAll()
        #expect(loaded.entries == written, "a second read gave different entries")
        #expect(loaded.termination == .complete)
    }

    @Test("A record too big for the real log is refused here too")
    @MainActor
    func aRecordTooBigIsRefused() async throws {
        let tiny = MemoryLogStore(maximumRecordBytes: 64)
        await #expect(throws: (any Error).self) {
            _ = try await entries("this entry will not fit", into: tiny)
        }
        #expect(
            try await tiny.loadAll().entries.isEmpty,
            """
            The fake accepted a record the file log refuses, so nothing tested what happens when \
            an entry is too big to write down — and `try?` on a write that costs history is the \
            one thing this app is not allowed to do.
            """)
    }

    @Test("A space is read only by the one person named on it, as a share naming one participant is")
    func aSpaceIsReadOnlyByThePersonItNames() async throws {
        let mailbox = InMemoryMailbox()
        let pair = try await linked(mailbox)
        let (_, asStranger) = try peers(Identity.generate(), Identity.generate())
        let stranger = Pairs(
            me: asStranger.me, hints: [pair.toBob.me: pair.toBob.secret.pairHint],
            accounts: [pair.toBob.me: [LocalPairStore.account(of: pair.toBob.me)]])
        let id = AttachmentID()
        let sealed = Data((0..<64).map { _ in UInt8.random(in: .min ... .max) })
        let link = try await mailbox.space(
            for: pair.toBob.them, naming: LocalPairStore.account(of: pair.toBob.them), in: pair.alice)
        let copies = try OutgoingAttachment(
            id: id, ciphertext: sealed, recipients: [pair.toBob.them: pair.toBob.outgoingTag(window: 1)]
        ).copies(between: { _ in pair.toBob.secret })
        let copy = try #require(copies.copies[pair.toBob.them])

        try await mailbox.upload(copies, in: pair.alice)

        #expect(await mailbox.download(copy.name, of: id, from: pair.toBob.me, in: pair.bob) == copy.sealed)
        #expect(
            await mailbox.join(PairLink(account: await mailbox.account(in: pair.alice), url: link), of: pair.toBob.me, in: stranger)
                == .notYetNamed,
            "somebody holding the link but not named on it got in")
        #expect(
            await mailbox.download(copy.name, of: id, from: pair.toBob.me, in: stranger) == nil,
            "a photo reached somebody its space was not shared with")
    }

    @Test("Naming somebody else on a space shuts out the person named before")
    func namingSomebodyElseShutsOutTheFirst() async throws {
        let mailbox = InMemoryMailbox()
        let pair = try await linked(mailbox)
        let tag = pair.toBob.outgoingTag(window: 1)
        try await mailbox.put(SyncPacket(wraps: [tag: Data(count: 8)], ciphertext: Data(count: 8)), to: pair.toBob.them, in: pair.alice)
        #expect(try await mailbox.fetch(from: pair.toBob.me, for: [tag], in: pair.bob).count == 1)

        _ = try await mailbox.space(for: pair.toBob.them, naming: "_somebody-else", in: pair.alice)
        #expect(
            try await mailbox.fetch(from: pair.toBob.me, for: [tag], in: pair.bob).isEmpty,
            "the person named before still read the space")
    }

    @Test("A receipt is written into the reader's own space and changes nothing in the sender's")
    func aReceiptStaysInTheReadersSpace() async throws {
        let mailbox = InMemoryMailbox()
        let pair = try await linked(mailbox)
        let tag = pair.toBob.outgoingTag(window: 1)
        let packet = SyncPacket(wraps: [tag: Data(count: 8)], ciphertext: Data(count: 8))
        try await mailbox.put(packet, to: pair.toBob.them, in: pair.alice)
        let before = try #require(await mailbox.everySentPacket[packet.id]?.contentDigest)

        try await mailbox.acknowledge(
            packet.id, from: pair.toBob.me, with: SealedReceipt(tag: tag, sealed: Data([1])), in: pair.bob)

        #expect(await mailbox.everySentPacket[packet.id]?.contentDigest == before, "a reader's receipt changed the packet")
        #expect(try await mailbox.sentPackets(in: pair.alice)[packet.id]?.receipts.count == 1)
    }
}

@MainActor
@Suite("The fake screen is no easier than Apple's")
struct TheFakeScreenIsNoEasierTests {
    @Test("With screening off, it refuses to look, as the real analyser does")
    func offRefuses() async {
        let screen = FakeMediaScreen(availability: .offInSystemSettings)
        await #expect(throws: FakeMediaScreen.Unavailable.self) {
            try await screen.isSensitive(image: LoadingPhotoForTheScreenFixtures.jpeg)
        }
    }

    @Test("Bytes that are not a picture are refused, not judged clear")
    func notAPictureIsRefused() async {
        let screen = FakeMediaScreen()
        await #expect(throws: FakeMediaScreen.NotAnImage.self) {
            try await screen.isSensitive(image: Data(repeating: 7, count: 400))
        }
        #expect((try? await screen.isSensitive(image: LoadingPhotoForTheScreenFixtures.jpeg)) == false)
    }

    @Test("A clip that is not on disk is refused")
    func aMissingClipIsRefused() async {
        let screen = FakeMediaScreen()
        await #expect(throws: CocoaError.self) {
            try await screen.isSensitive(videoAt: TestScratch.root.appending(path: "\(UUID()).mp4"))
        }
    }
}

enum LoadingPhotoForTheScreenFixtures {
    @MainActor static var jpeg: Data { MediaLoaderTests.onePixelJPEG }
}

@Suite("A choice is recorded even when it matches the default", .serialized)
@MainActor
struct AnsweringIsNotTheSameAsNotAnsweringTests {
    @Test("Choosing the value that was already the default still records an answer")
    func choosingTheDefaultStillRecords() async throws {
        let session = TestSession.make(keychain: InMemoryKeychainStore())
        await session.load()
        try await session.createIdentity(displayName: "Griff")

        #expect(session.isToldAboutRestores, "the fixture's default changed")
        await session.setToldAboutRestores(true)

        #expect(
            session.hasAnsweredAboutRestores,
            """
            Taking a preset that leaves a setting off recorded nothing, so "I chose Familiar and \\
            open" is indistinguishable from "I never answered". A preference with no stamp loses \\
            every merge against a device that has one, so the member's latest choice is silently \\
            overruled by an older one on another device they own.
            """)
    }

    @Test("Taking the focus settings that were already the default still records an answer")
    func choosingTheDefaultFocusStillRecords() async throws {
        let session = TestSession.make(keychain: InMemoryKeychainStore())
        await session.load()
        try await session.createIdentity(displayName: "Griff")

        await session.setFocusSharing(session.focusSharing)

        #expect(
            session.persisted.preferences.hasAnswered(\.sharesFocus),
            """
            The check-up asked whether to share when notifications are silenced, the member left it \
            as it was, and nothing was written down. `setFocusSharing` compared each field against \
            the *derived* value, and a preference nobody has set reads as its default — so the \
            whole composite short-circuited. Measured on a fresh device 2026-09-14: sharesFocus, \
            showsOthersFocus and showsPhotoOnOutpost were the three the check-up dropped after all \
            sixteen questions were answered.
            """)
        #expect(
            session.persisted.preferences.hasAnswered(\.showsOthersFocus),
            "the second half of the same composite was dropped")
    }

    @Test("Answering the focus settings again with the same values does not write again")
    func answeringFocusTwiceDoesNotWriteTwice() async throws {
        let session = TestSession.make(keychain: InMemoryKeychainStore())
        await session.load()
        try await session.createIdentity(displayName: "Griff")

        await session.setFocusSharing(session.focusSharing)
        let first = session.persisted.preferences.sharesFocus?.stamp.at
        await session.setFocusSharing(session.focusSharing)

        #expect(
            session.persisted.preferences.sharesFocus?.stamp.at == first,
            "an unchanged answer was stamped again, so every visit to the settings churns the feed")
    }

    @Test("Choosing the notification level that was already the default still records an answer")
    func choosingTheDefaultNotificationLevelStillRecords() async throws {
        let session = TestSession.make(keychain: InMemoryKeychainStore())
        await session.load()
        try await session.createIdentity(displayName: "Griff")

        await session.setNotificationLevel(session.notificationLevel)

        #expect(
            session.persisted.preferences.hasAnswered(\.notificationLevel),
            """
            The same shape one setting over: choosing the level that was already showing wrote \
            nothing, so it loses every merge against another device that has an older answer.
            """)
    }

    @Test("Answering again with the same value does not write a second time")
    func answeringTwiceDoesNotWriteTwice() async throws {
        let session = TestSession.make(keychain: InMemoryKeychainStore())
        await session.load()
        try await session.createIdentity(displayName: "Griff")

        await session.setToldAboutRestores(true)
        let first = session.answerStampAboutRestores
        await session.setToldAboutRestores(true)

        #expect(
            session.answerStampAboutRestores == first,
            "an unchanged answer was stamped again, so every check-up would churn the feed")
    }
}
