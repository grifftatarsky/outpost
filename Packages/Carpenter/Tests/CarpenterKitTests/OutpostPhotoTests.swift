import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("A photo on an Outpost", .serialized)
struct OutpostPhotoTests {
    @Test("A photo becomes a post with a picture, and its caption is the words")
    func aPhotoIsAPost() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")

        try await alice.post(SendingPhotoTests.photo(caption: "Look at this"), through: mailbox)
        try await alice.post(SendingPhotoTests.photo(), through: mailbox)

        let feed = alice.feed()  // newest first
        #expect(feed.count == 2)
        let captioned = try #require(feed.last)
        #expect(!captioned.media.isEmpty)
        #expect(captioned.body == "Look at this")
        let bare = try #require(feed.first)
        let media = try #require(bare.media.first)
        #expect(bare.body.isEmpty, "a photo alone has no words, not a placeholder line")
        #expect(await alice.holdsAttachment(media.id), "the sender's own copy was not kept")
        #expect(await mailbox.uploadCount == 2)
        #expect(await mailbox.storedAttachmentCount == 2, "the bytes are in the outbox for an audience")
    }

    @Test("The sweep leaves a wall photo alone, and a relaunch still draws it")
    func sweepLeavesItAndARelaunchKeepsIt() async throws {
        let keychain = InMemoryKeychainStore()
        let media = MemoryMediaStore()
        let directory = URL.temporaryDirectory.appending(path: "carpenter-wall-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make(keychain: keychain, at: directory, media: media)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        try await alice.post(SendingPhotoTests.photo(caption: "Kept"), through: mailbox)

        try await alice.sync(through: mailbox, media: mailbox)
        #expect(await mailbox.storedAttachmentCount == 1, "the sweep took a photo an entry names")

        let again = TestSession.make(keychain: keychain, at: directory, media: media)
        await again.load()
        let post = try #require(again.feed().first)
        let picture = try #require(post.media.first)
        #expect(post.body == "Kept")
        #expect(await again.holdsAttachment(picture.id))
        let opened = try await again.attachmentData(for: picture, sentBy: post.author.id, through: mailbox)
        #expect(opened == SendingPhotoTests.photo(caption: "Kept").bytes)
    }

    @Test("An upload that fails posts nothing and keeps nothing")
    func uploadFailurePostsNothing() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")

        await mailbox.failNextWrite(with: .unavailable)
        await #expect(throws: (any Error).self) {
            try await alice.post(SendingPhotoTests.photo(), through: mailbox)
        }
        #expect(alice.feed().isEmpty, "an entry was written for bytes nobody can fetch")
        #expect(await mailbox.storedAttachmentCount == 0)
    }
}

@MainActor
@Suite("A gallery on a post", .serialized)
struct OutpostGalleryTests {
    private static func clip(caption: String? = nil) -> PreparedMedia {
        PreparedMedia(
            kind: .video, width: 960, height: 540,
            bytes: Data((0..<9_000).map { UInt8($0 % 251) }),
            preview: Data(repeating: 0xCD, count: 700), caption: caption, duration: 12)
    }

    private func member() async throws -> AppSession {
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        return alice
    }

    @Test("Several pictures go as one post, and the words are the caption on the first")
    func severalPicturesAreOnePost() async throws {
        let mailbox = InMemoryMailbox()
        let alice = try await member()

        try await alice.post(
            [
                SendingPhotoTests.photo(caption: "three of them"),
                SendingPhotoTests.photo(),
                SendingPhotoTests.photo(),
            ], through: mailbox)

        #expect(alice.feed().count == 1, "a gallery became several posts")
        let post = try #require(alice.feed().first)
        #expect(post.media.count == 3)
        #expect(post.body == "three of them")
        #expect(await mailbox.uploadCount == 3)
        for picture in post.media {
            #expect(await alice.holdsAttachment(picture.id), "a picture in the gallery was not kept")
        }
    }

    @Test("A clip is a picture on a post like any other, and keeps its length")
    func aClipOnAPost() async throws {
        let mailbox = InMemoryMailbox()
        let alice = try await member()

        try await alice.post([Self.clip(caption: "a moving one"), SendingPhotoTests.photo()], through: mailbox)

        let post = try #require(alice.feed().first)
        #expect(post.media.count == 2)
        #expect(post.media[0].kind == .video)
        #expect(post.media[0].duration == 12)
        #expect(post.media[1].kind == .image)
        #expect(post.body == "a moving one")
    }

    @Test("More than four is refused before anything is uploaded")
    func moreThanFourIsRefused() async throws {
        let mailbox = InMemoryMailbox()
        let alice = try await member()
        let five = (0..<5).map { _ in SendingPhotoTests.photo() }

        await #expect(throws: AppSessionError.tooManyPictures) {
            try await alice.post(five, through: mailbox)
        }
        #expect(alice.feed().isEmpty)
        #expect(await mailbox.uploadCount == 0, "something went up before the refusal")
    }

    @Test("An upload that fails takes back the ones already up")
    func failureTakesBackWhatWentUp() async throws {
        let mailbox = InMemoryMailbox()
        let alice = try await member()

        await mailbox.failUpload(number: 2, with: .unavailable)
        await #expect(throws: (any Error).self) {
            try await alice.post(
                [SendingPhotoTests.photo(), SendingPhotoTests.photo()], through: mailbox)
        }

        #expect(alice.feed().isEmpty, "an entry was written for a gallery that never went up")
        #expect(
            await mailbox.storedAttachmentCount == 0,
            "the picture that did go up was left in the outbox with nothing naming it")
    }

    @Test("A build that does not know about a gallery still reads its first picture")
    func olderBuildsReadTheFirst() throws {
        let reference = AttachmentReference(
            id: AttachmentID(), key: Data(repeating: 1, count: 32),
            digest: Data(repeating: 2, count: 32), byteCount: 40)
        let one = MediaBody(
            attachment: reference, kind: .image, width: 8, height: 6, preview: nil,
            caption: "as it was")

        let asWritten = try JSONEncoder().encode(one)
        var fields = try #require(
            try JSONSerialization.jsonObject(with: asWritten) as? [String: Any])
        fields.removeValue(forKey: "extras")
        let older = try JSONSerialization.data(withJSONObject: fields)

        let read = try JSONDecoder().decode(MediaBody.self, from: older)
        #expect(read.extras.isEmpty)
        #expect(read.caption == "as it was")
        #expect(read.all.count == 1)
        #expect(read.attachment == reference)
    }

    @Test("A picture this build cannot read costs that picture and not the gallery")
    func oneUnreadableExtraDoesNotLoseTheRest() throws {
        func picture(_ seed: UInt8, caption: String? = nil) -> MediaBody {
            MediaBody(
                attachment: AttachmentReference(
                    id: AttachmentID(), key: Data(repeating: seed, count: 32),
                    digest: Data(repeating: seed, count: 32), byteCount: 10),
                kind: .image, width: 4, height: 3, preview: nil, caption: caption)
        }
        func fields(_ body: MediaBody) throws -> [String: Any] {
            try #require(
                try JSONSerialization.jsonObject(with: try JSONEncoder().encode(body))
                    as? [String: Any])
        }
        var head = try fields(picture(1, caption: "the first one"))
        var unreadable = try fields(picture(2))
        unreadable["kind"] = "hologram"
        head["extras"] = [unreadable, try fields(picture(3))]

        let read = try JSONDecoder().decode(
            MediaBody.self, from: try JSONSerialization.data(withJSONObject: head))

        #expect(read.caption == "the first one", "the head was lost with the extra")
        #expect(read.extras.count == 1, "an unreadable picture took a readable one with it")
        #expect(read.all.count == 2)
    }

    @Test("A gallery is one level deep")
    func galleriesDoNotNest() {
        func picture(_ seed: UInt8, extras: [MediaBody] = []) -> MediaBody {
            MediaBody(
                attachment: AttachmentReference(
                    id: AttachmentID(), key: Data(repeating: seed, count: 32),
                    digest: Data(repeating: seed, count: 32), byteCount: 10),
                kind: .image, width: 4, height: 3, preview: nil, caption: nil, extras: extras)
        }
        let nested = picture(1, extras: [picture(2, extras: [picture(3)])])
        #expect(nested.all.count == 2)
        #expect(nested.all.allSatisfy { $0.extras.isEmpty })
    }
}

@MainActor
@Suite("A gallery's pictures are all named", .serialized)
struct GalleryAttachmentTests {
    private func joined() async throws -> (
        alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox
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
        try await alice.sync(through: mailbox, media: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        for _ in 0..<4 {
            try await alice.sync(through: mailbox, media: mailbox)
            try await bob.sync(through: mailbox, media: mailbox)
        }
        return (alice, bob, mailbox)
    }

    @Test("The sweep leaves every picture of a gallery, not only the first")
    func sweepKeepsTheWholeGallery() async throws {
        let mailbox = InMemoryMailbox()
        let keychain = InMemoryKeychainStore()
        let media = MemoryMediaStore()
        let directory = URL.temporaryDirectory.appending(path: "carpenter-sweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let alice = TestSession.make(keychain: keychain, at: directory, media: media)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        try await alice.post(
            [
                SendingPhotoTests.photo(caption: "four of them"),
                SendingPhotoTests.photo(),
                SendingPhotoTests.photo(),
                SendingPhotoTests.photo(),
            ], through: mailbox)
        #expect(await mailbox.storedAttachmentCount == 4, "precondition: four pictures went up")

        let again = TestSession.make(keychain: keychain, at: directory, media: media)
        await again.load()
        try await again.sync(through: mailbox, media: mailbox)

        #expect(
            await mailbox.storedAttachmentCount == 4,
            "the sweep deleted pictures an entry names")
        let post = try #require(again.feed().first)
        #expect(post.media.count == 4)
        for picture in post.media {
            #expect(await again.holdsAttachment(picture.id), "a picture was dropped locally")
        }
    }

    @Test("A round fetches every picture of a gallery it receives")
    func roundFetchesTheWholeGallery() async throws {
        let (alice, bob, mailbox) = try await joined()
        try await alice.post(
            [SendingPhotoTests.photo(caption: "three"), SendingPhotoTests.photo(),
             SendingPhotoTests.photo()], through: mailbox)
        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        for _ in 0..<5 {
            try await alice.sync(through: mailbox, media: mailbox)
            try await bob.sync(through: mailbox, media: mailbox)
        }

        let post = try #require(bob.feed().first)
        #expect(post.media.count == 3)
        for picture in post.media {
            #expect(
                await bob.holdsAttachment(picture.id),
                "the entry arrived and one of its pictures did not")
        }
    }
}
