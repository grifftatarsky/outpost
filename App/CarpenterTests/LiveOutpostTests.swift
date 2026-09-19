import CarpenterApp
import CarpenterCloudKit
import CarpenterKit
import CloudKit
import Foundation
import Testing

@Suite(
    "An Outpost on a real CloudKit account",
    .enabled(if: LiveCloudKit.isAsked),
    .serialized)
@MainActor
struct LiveOutpostTests {

    private func picture(_ seed: UInt8) -> Data {
        var bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00])
        bytes.append(contentsOf: (0..<4096).map { _ in UInt8.random(in: .min ... .max) })
        bytes.append(seed)
        bytes.append(contentsOf: [0xFF, 0xD9])
        return bytes
    }

    private func media(_ seed: UInt8, caption: String?) -> PreparedMedia {
        PreparedMedia(
            kind: .image, width: 64, height: 64, bytes: picture(seed), preview: picture(seed &+ 1),
            caption: caption)
    }

    private func withAudience(_ rig: LiveRig.Pair) async throws {
        let bob = try #require(rig.bob.enrolment?.identity.id)
        try await rig.alice.allowOutpost(bob, everything: true)
        try await LiveRig.settle([rig.alice, rig.bob], through: rig.mailbox)
    }

    @Test("A post with a photo crosses, and the reader can fetch the bytes")
    func aPhotoCrossesToAReader() async throws {
        let rig = try await LiveRig.joined(label: "outpostphoto")
        defer { Task { await LiveRig.tearDown(rig.zone) } }
        try await withAudience(rig)

        let sent = media(7, caption: "the gasbag at dusk")
        try await rig.alice.post(sent, through: rig.mailbox)
        try await LiveRig.settle([rig.alice, rig.bob], through: rig.mailbox, rounds: 6)

        let seen = rig.bob.feed()
        let post = try #require(
            seen.first { $0.body == "the gasbag at dusk" },
            """
            A photo posted to an Outpost never reached a reader over real CloudKit. Every test for \
            this ran against the in-memory mailbox. Feed held: \(seen.map(\.body))
            """)
        let attachment = try #require(
            post.media.first, "the post crossed but carried no picture with it")

        let alice = try #require(rig.alice.enrolment?.identity.id)
        let bytes = try await rig.bob.attachmentData(
            for: attachment, sentBy: alice, through: rig.mailbox)
        #expect(
            bytes == sent.bytes,
            """
            The reader fetched the attachment and the bytes were not the ones that were sent. An \
            attachment goes as a CKAsset rather than inside the record, which is a different path \
            from everything else in this file.
            """)
    }

    @Test("An edit and a deletion of a post both reach the reader")
    func editsAndDeletionsReachTheReader() async throws {
        let rig = try await LiveRig.joined(label: "outpostedit")
        defer { Task { await LiveRig.tearDown(rig.zone) } }
        try await withAudience(rig)

        try await rig.alice.send("frist light", to: nil)
        try await rig.alice.send("this one goes", to: nil)
        try await LiveRig.settle([rig.alice, rig.bob], through: rig.mailbox, rounds: 6)

        let typo = try #require(rig.alice.outpost().first { $0.body == "frist light" })
        let doomed = try #require(rig.alice.outpost().first { $0.body == "this one goes" })
        try await rig.alice.edit(typo.id, to: "first light")
        try await rig.alice.withdraw(doomed.id)
        try await LiveRig.settle([rig.alice, rig.bob], through: rig.mailbox, rounds: 6)

        let seen = rig.bob.feed()
        #expect(
            seen.contains { $0.body == "first light" },
            "the edit never reached the reader; they still hold the words their author replaced")
        #expect(
            !seen.contains { $0.body == "this one goes" && !$0.isWithdrawn },
            "the deletion never reached the reader; they still draw what was taken back")
    }

    @Test("A wall's own face crosses, and the reader draws it")
    func theWallsFaceCrosses() async throws {
        let rig = try await LiveRig.joined(label: "outpostface")
        defer { Task { await LiveRig.tearDown(rig.zone) } }
        try await withAudience(rig)

        await rig.bob.setShowsOthersAvatars(true)
        await rig.alice.setSharesAvatar(true)
        await rig.alice.setShowsPhotoOnOutpost(true)
        try await LiveRig.settle([rig.alice, rig.bob], through: rig.mailbox)

        let face = picture(21)
        try await rig.alice.shareOutpostPhoto(face, through: rig.mailbox)
        try await LiveRig.settle([rig.alice, rig.bob], through: rig.mailbox, rounds: 6)

        let alice = try #require(rig.alice.enrolment?.identity.id)
        let reference = try #require(
            rig.bob.sharedOutpostPhotoReference(of: alice),
            """
            The reader has no reference to the wall's own picture. A member's Outpost draws their \
            own avatar unless they override it there, and the override is what this sends.
            """)

        let bytes = try await rig.bob.downloadSharedPhoto(
            reference, from: alice, through: rig.mailbox)
        #expect(bytes == face, "the wall's face arrived as different bytes than were shared")
    }

    @Test("What is new on a wall is new to the reader and not to its author")
    func whatIsNewIsNewToTheReader() async throws {
        let rig = try await LiveRig.joined(label: "outpostunseen")
        defer { Task { await LiveRig.tearDown(rig.zone) } }
        try await withAudience(rig)

        let alice = try #require(rig.alice.enrolment?.identity.id)
        try await rig.alice.post(media(31, caption: "something new"), through: rig.mailbox)
        try await LiveRig.settle([rig.alice, rig.bob], through: rig.mailbox, rounds: 6)

        #expect(
            rig.bob.unseenPosts(from: alice) > 0,
            "a post crossed and the reader's wall did not light as unseen")
        #expect(
            rig.alice.unseenPosts(from: alice) == 0,
            "an author's own post counted as unseen to them, which would light their own rail")

        await rig.bob.markOutpostSeen(from: alice)
        #expect(
            rig.bob.unseenPosts(from: alice) == 0,
            "the mark is device-local, so reading it should clear it without a round")
    }

    @Test("A comment crosses back to the wall's owner")
    func aCommentCrossesBack() async throws {
        let rig = try await LiveRig.joined(label: "outpostcomment")
        defer { Task { await LiveRig.tearDown(rig.zone) } }
        try await withAudience(rig)

        try await rig.alice.post(media(41, caption: "say something"), through: rig.mailbox)
        try await LiveRig.settle([rig.alice, rig.bob], through: rig.mailbox, rounds: 6)

        let post = try #require(
            rig.bob.feed().first { $0.body == "say something" },
            "the post never reached the reader, so there is nothing to comment on")
        try await rig.bob.comment(on: post, text: "the light is good")
        try await LiveRig.settle([rig.alice, rig.bob], through: rig.mailbox, rounds: 6)

        let mine = try #require(rig.alice.outpost().first { $0.body == "say something" })
        let comments = rig.alice.comments(on: mine).map(\.body)
        #expect(
            comments.contains("the light is good"),
            """
            A reader's comment did not reach the wall it was written on. The reverse channel is \
            what carries it, and it is the seam a wall's whole conversation depends on. Held: \
            \(comments)
            """)
    }
}
