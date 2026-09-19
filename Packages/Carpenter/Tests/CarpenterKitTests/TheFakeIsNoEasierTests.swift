@testable import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("The in-memory mailbox is no easier than the real one", .serialized)
struct TheFakeIsNoEasierTests {
    private func tag() -> RecipientTag {
        RecipientTag(rawValue: Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }

    @Test("A packet too big for a real record is refused here too")
    func aPacketTooBigIsRefused() async throws {
        let mailbox = InMemoryMailbox()
        let mine = tag()
        let huge = SyncPacket(
            wraps: [mine: Data(count: 32)],
            ciphertext: Data(count: MailboxRules.recordByteCeiling + 1))

        await #expect(throws: MailboxError.self) {
            try await mailbox.put(huge)
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
        let mine = tag()
        let big = SyncPacket(
            wraps: [mine: Data(count: 32)], ciphertext: Data(count: SyncSession.packetByteBudget))

        try await mailbox.put(big)
        #expect(
            await mailbox.storedPacketCount == 1,
            "a packet at the app's own budget was refused, so the budget is above the ceiling")
    }

    @Test("An upload is not sweepable until it has settled")
    func anUploadIsNotSweepableUntilSettled() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let mine = tag()
        let id = AttachmentID()

        try await mailbox.upload(
            OutgoingAttachment(id: id, ciphertext: Data(count: 16), recipients: [mine]))

        #expect(
            try await mailbox.pendingAttachments()[id] == [mine],
            "a fresh upload did not report who still owes it")
        #expect(
            try await mailbox.sweepableAttachments()[id] == nil,
            """
            A fresh upload was already sweepable. The two questions are different: who still owes \
            this, and what is old enough to be an orphan. Answering both with one method is what \
            let a new reader wipe the outstanding list of a photo posted minutes earlier.
            """)

        clock.advance(by: MailboxRules.sweepAge + 1)
        #expect(
            try await mailbox.sweepableAttachments()[id] == [mine],
            "an upload older than the sweep age never became sweepable")
    }

    @MainActor
    private func entries(_ text: String, into log: MemoryLogStore) async throws -> [Entry] {
        let session = AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(), log: log,
                documents: FileDocumentStore(
                    url: URL.temporaryDirectory.appending(
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

    @Test("A photo is not handed to somebody it was not sent to")
    func aPhotoIsNotHandedToAStranger() async throws {
        let mailbox = InMemoryMailbox()
        let mine = tag()
        let stranger = tag()
        let id = AttachmentID()
        let sealed = Data((0..<64).map { _ in UInt8.random(in: .min ... .max) })

        try await mailbox.upload(
            OutgoingAttachment(id: id, ciphertext: sealed, recipients: [mine]))

        #expect(try await mailbox.download(id, hint: [mine]) == sealed)
        #expect(
            try await mailbox.download(id, hint: [stranger]) == nil,
            """
            The fake handed a photo's bytes to a tag it was never addressed to. The real mailbox \
            resolves a zone from the recipient's address and finds nothing, so a test that proved \
            somebody could collect a photo they were not sent was proving it against a fake that \
            does not check. The bytes are sealed either way — but a test that cannot tell the \
            difference is the one that lets the seal slip.
            """)
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
            try await screen.isSensitive(videoAt: URL.temporaryDirectory.appending(path: "\(UUID()).mp4"))
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
