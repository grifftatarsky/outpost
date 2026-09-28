@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Asking for a photo again", .serialized)
@MainActor
struct AskingForAPhotoAgainTests {
    @MainActor
    private struct Pair {
        let alice: AppSession
        let bob: AppSession
        let room: RoomID
        let mailbox: InMemoryMailbox
        let clock: TestClock

        var aliceID: ParticipantID { alice.enrolment!.identity.id }
        var bobID: ParticipantID { bob.enrolment!.identity.id }

        func round(_ times: Int = 2) async throws {
            for _ in 0..<times {
                try await alice.sync(through: mailbox, media: mailbox)
                try await bob.sync(through: mailbox, media: mailbox)
            }
        }
    }

    private func pair() async throws -> Pair {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Darkroom")
        let invite = try await alice.invite(joinerCode: await bob.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await bob.redeem(inviteCode: try invite.encoded())
        let pair = Pair(alice: alice, bob: bob, room: room, mailbox: mailbox, clock: clock)
        try await pair.round(4)
        return pair
    }

    private func photoBobHasLost(_ pair: Pair) async throws -> (id: AttachmentID, entry: EntryHash) {
        try await pair.alice.send(SendingPhotoTests.photo(), to: pair.room, through: pair.mailbox)
        let message = try #require(pair.alice.messages(in: pair.room).last)
        let id = try #require(message.media?.id)
        try await pair.round(2)
        try #require(await pair.bob.holdsAttachment(id), "precondition: Bob collected it")
        try #require(!(await pair.mailbox.storedAttachmentIDs.contains(id)), "precondition: Alice cleared it")
        try await pair.bob.storage.media.remove(id)
        let media = try #require(pair.bob.messages(in: pair.room).last { $0.media?.id == id }?.media)
        try #require(
            try await pair.bob.attachmentData(for: media, sentBy: pair.aliceID, through: pair.mailbox) == nil,
            "precondition: Bob no longer has it and iCloud has let it go")
        return (id, message.id.entry)
    }

    @Test("Somebody a photo was sent to asks for it again, the sender sends it, and it opens")
    func askedSentAndOpened() async throws {
        let pair = try await pair()
        let (id, entry) = try await photoBobHasLost(pair)

        #expect(pair.bob.canAskAgain(for: id, sentBy: pair.aliceID))
        #expect(await pair.bob.askAgain(for: id, sentBy: pair.aliceID))
        #expect(pair.bob.isAskedFor(id), "the photo does not say it was asked for")
        try await pair.round(2)

        let requests = pair.alice.photoRequests(in: pair.room)
        #expect(requests.count == 1, "the ask never reached the sender")
        let request = try #require(requests.first)
        #expect(request.person.id == pair.bobID)
        #expect(request.media.id == id)
        #expect(request.message.entry == entry, "the request cannot take the sender to the message")

        try await pair.alice.sendAgain(request.id, through: pair.mailbox)
        #expect(pair.alice.photoRequests(in: pair.room).isEmpty, "an answered ask stayed on the list")
        pair.clock.advance(by: 61)
        try await pair.round(2)

        #expect(await pair.bob.holdsAttachment(id), "the photo sent again never arrived")
        #expect(!pair.bob.isAskedFor(id), "the photo arrived and still says it was asked for")
        let media = try #require(pair.bob.messages(in: pair.room).last { $0.media?.id == id }?.media)
        #expect(
            try await pair.bob.attachmentData(for: media, sentBy: pair.aliceID, through: pair.mailbox)
                == SendingPhotoTests.photo().bytes)
        try await pair.round(1)
        #expect(
            !(await pair.mailbox.storedAttachmentIDs.contains(id)),
            "the photo sent again stayed in the outbox after the one who asked had it")
    }

    @Test("Nothing goes back up until the sender says so")
    func nothingWithoutTheSender() async throws {
        let pair = try await pair()
        let (id, _) = try await photoBobHasLost(pair)
        await pair.bob.askAgain(for: id, sentBy: pair.aliceID)
        let uploads = await pair.mailbox.uploadCount
        try await pair.round(3)

        #expect(pair.alice.photoRequests(in: pair.room).count == 1)
        #expect(await pair.mailbox.uploadCount == uploads, "asking made the sender upload without being told to")
        #expect(pair.bob.isAskedFor(id), "an ask nobody answered stopped saying so")
    }

    @Test("An ask about a photo that was not sent to the one asking never shows up")
    func onlyTheRecipientsCanAsk() async throws {
        let pair = try await pair()
        let (id, entry) = try await photoBobHasLost(pair)

        let elsewhere = try await pair.alice.createRoom(named: "Just me")
        try await pair.alice.send(SendingPhotoTests.photo(), to: elsewhere, through: pair.mailbox)
        let theirs = try #require(pair.alice.messages(in: elsewhere).last)
        let theirID = try #require(theirs.media?.id)

        let stranger = ParticipantID(rawValue: WideID.of([0x42]))
        pair.alice.takeAsks([PhotoAsk(entry: entry, attachment: id)], from: stranger)
        pair.alice.takeAsks([PhotoAsk(entry: theirs.id.entry, attachment: theirID)], from: pair.bobID)
        pair.alice.takeAsks([PhotoAsk(entry: entry, attachment: AttachmentID())], from: pair.bobID)

        try await pair.bob.send(SendingPhotoTests.photo(), to: pair.room, through: pair.mailbox)
        let bobs = try #require(pair.bob.messages(in: pair.room).last)
        try await pair.round(2)
        try #require(
            pair.alice.messages(in: pair.room).contains { $0.id == bobs.id },
            "precondition: Alice has Bob's photo, so refusing an ask for it is about who sent it")
        pair.alice.takeAsks([PhotoAsk(entry: bobs.id.entry, attachment: try #require(bobs.media?.id))], from: pair.bobID)

        #expect(
            pair.alice.persisted.photoAsks.isEmpty,
            """
            An ask was kept that the sender should have refused: from somebody the photo was not \
            sent to, for a photo in a room the asker is not in, naming a photo the message does not \
            hold, or for a photo somebody else sent.
            """)
        #expect(pair.alice.photoRequests(in: pair.room).isEmpty)
        #expect(pair.alice.photoRequests(in: elsewhere).isEmpty)
    }

    @Test("Somebody no longer in the room cannot ask, and an ask from before they went is not shown")
    func leavingEndsTheAsk() async throws {
        let pair = try await pair()
        let (id, entry) = try await photoBobHasLost(pair)
        pair.alice.takeAsks([PhotoAsk(entry: entry, attachment: id)], from: pair.bobID)
        try #require(pair.alice.photoRequests(in: pair.room).count == 1, "precondition: the ask counts")

        try await pair.alice.remove(pair.bobID, from: pair.room)
        try await pair.round(2)
        #expect(pair.alice.photoRequests(in: pair.room).isEmpty, "an ask from somebody removed is still shown")
        await #expect(throws: PhotoAskError.noLongerAsked) {
            try await pair.alice.sendAgain(
                PhotoRequest.ID(person: pair.bobID, attachment: id), through: pair.mailbox)
        }
        #expect(!pair.bob.canAskAgain(for: id, sentBy: pair.aliceID), "somebody removed was offered the ask")
        #expect(!(await pair.bob.askAgain(for: id, sentBy: pair.aliceID)))
    }

    @Test("An ask is kept once per person and photo, and a dismissed one is gone")
    func oneAskAndDismissal() async throws {
        let pair = try await pair()
        let (id, entry) = try await photoBobHasLost(pair)
        for _ in 0..<3 { pair.alice.takeAsks([PhotoAsk(entry: entry, attachment: id)], from: pair.bobID) }
        #expect(pair.alice.photoRequests(in: pair.room).count == 1, "the same ask was listed more than once")

        await pair.alice.dismissPhotoRequest(PhotoRequest.ID(person: pair.bobID, attachment: id))
        #expect(pair.alice.photoRequests(in: pair.room).isEmpty)
    }

    @Test("A sender who no longer holds the photo is told, and nothing is uploaded")
    func notHeldIsSaid() async throws {
        let pair = try await pair()
        let (id, entry) = try await photoBobHasLost(pair)
        pair.alice.takeAsks([PhotoAsk(entry: entry, attachment: id)], from: pair.bobID)
        try await pair.alice.storage.media.remove(id)
        let uploads = await pair.mailbox.uploadCount

        await #expect(throws: PhotoAskError.notHeldHere) {
            try await pair.alice.sendAgain(PhotoRequest.ID(person: pair.bobID, attachment: id), through: pair.mailbox)
        }
        #expect(await pair.mailbox.uploadCount == uploads)
        #expect(pair.alice.photoRequests(in: pair.room).count == 1, "a failed send took the ask off the list")
    }

    @Test("Nobody asks for their own photo")
    func ownPhotosAreNotAskedFor() async throws {
        let pair = try await pair()
        try await pair.alice.send(SendingPhotoTests.photo(), to: pair.room, through: pair.mailbox)
        let id = try #require(pair.alice.messages(in: pair.room).last?.media?.id)
        #expect(!pair.alice.canAskAgain(for: id, sentBy: pair.aliceID))
        #expect(!(await pair.alice.askAgain(for: id, sentBy: pair.aliceID)))
    }
}
