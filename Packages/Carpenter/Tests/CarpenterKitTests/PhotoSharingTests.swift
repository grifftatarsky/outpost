@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Sharing a photo", .serialized)
struct PhotoSharingTests {
    private static let photo = Data(repeating: 0xAB, count: 4_000)
    private static let secondPhoto = Data(repeating: 0xCD, count: 3_000)

    private func joined() async throws -> (alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox, room: ConversationID) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle(alice, bob, mailbox)
        return (alice, bob, mailbox, room)
    }

    private func settle(_ a: AppSession, _ b: AppSession, _ mailbox: InMemoryMailbox) async throws {
        for _ in 0..<2 {
            try await a.sync(through: mailbox)
            try await b.sync(through: mailbox)
        }
    }

    @Test("A round that meets somebody new says so, once")
    func meetingSomebodyNewAsksForAnotherRound() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        try await alice.sync(through: mailbox)
        #expect(!alice.metSomebodyNew, "a round with no peers has met nobody")

        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())

        var announced = 0
        for step in 0..<6 {
            try await alice.sync(through: mailbox)
            if alice.metSomebodyNew { announced += 1 }
            if step == 0 {
                try await bob.accept(
                    invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
            }
            try await bob.sync(through: mailbox)
        }
        #expect(announced == 1, "a new peer asks for one extra round, not one every round")
    }

    @Test("A shared photo stands in the outbox, and a peer who shows photos collects it without acknowledging")
    func sharedAndCollected() async throws {
        let (alice, bob, mailbox, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)

        try await alice.sharePhoto(Self.photo, through: mailbox)
        #expect(await mailbox.storedAttachmentCount == 0, "nothing goes up while Share my photo is off")

        await alice.setSharesAvatar(true)
        try await alice.sharePhoto(Self.photo, through: mailbox)
        try await settle(alice, bob, mailbox)
        #expect(await mailbox.storedAttachmentCount == 1)

        #expect(bob.sharedPhotoReference(of: aliceID) == nil, "nothing is collected while Show others' photos is off")
        await bob.setShowsOthersAvatars(true)
        let reference = try #require(bob.sharedPhotoReference(of: aliceID))
        let collected = try await bob.downloadSharedPhoto(reference, from: aliceID, through: mailbox)
        #expect(collected == Self.photo)
        #expect(await mailbox.attachmentAcknowledgeCount == 0, "acknowledging is what lets a sender delete")
        #expect(await mailbox.storedAttachmentCount == 1, "the photo stays up for the next device")
    }

    @Test("Replacing the photo leaves one attachment and no history")
    func replaced() async throws {
        let (alice, bob, mailbox, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        await alice.setSharesAvatar(true)
        await bob.setShowsOthersAvatars(true)

        try await alice.sharePhoto(Self.photo, through: mailbox)
        try await settle(alice, bob, mailbox)
        let first = try #require(bob.sharedPhotoReference(of: aliceID))

        try await alice.sharePhoto(Self.secondPhoto, through: mailbox)
        try await settle(alice, bob, mailbox)
        let second = try #require(bob.sharedPhotoReference(of: aliceID))
        #expect(second.id != first.id)
        #expect(await mailbox.storedAttachmentCount == 1, "the old photo is deleted, not kept")
        #expect(try await bob.downloadSharedPhoto(first, from: aliceID, through: mailbox) == nil)
        #expect(try await bob.downloadSharedPhoto(second, from: aliceID, through: mailbox) == Self.secondPhoto)
    }

    @Test("Taking the photo down withdraws the pointer and deletes the bytes")
    func withdrawn() async throws {
        let (alice, bob, mailbox, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        await alice.setSharesAvatar(true)
        await bob.setShowsOthersAvatars(true)
        try await alice.sharePhoto(Self.photo, through: mailbox)
        try await settle(alice, bob, mailbox)
        let reference = try #require(bob.sharedPhotoReference(of: aliceID))

        await alice.withdrawPhoto(through: mailbox)
        try await settle(alice, bob, mailbox)
        #expect(bob.sharedPhotoReference(of: aliceID) == nil)
        #expect(alice.ownPhotoReference == nil)
        #expect(await mailbox.storedAttachmentCount == 0)
        #expect(try await bob.downloadSharedPhoto(reference, from: aliceID, through: mailbox) == nil)
    }

    @Test("A room made after the photo went up is told where it is")
    func lateRoomIsTold() async throws {
        let (alice, _, mailbox, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        await alice.setSharesAvatar(true)
        try await alice.sharePhoto(Self.photo, through: mailbox)
        let reference = try #require(alice.ownPhotoReference)

        let later = try await alice.createRoom(named: "Kitchen")
        #expect(alice.announcedPhoto(of: aliceID, in: later) == .some(reference))
    }

    @Test("The sweep leaves a standing photo alone")
    func sweepKeepsIt() async throws {
        let (alice, _, mailbox, _) = try await joined()
        await alice.setSharesAvatar(true)
        try await alice.sharePhoto(Self.photo, through: mailbox)
        try await alice.sync(through: mailbox)
        #expect(await mailbox.storedAttachmentCount == 1)
    }
}
