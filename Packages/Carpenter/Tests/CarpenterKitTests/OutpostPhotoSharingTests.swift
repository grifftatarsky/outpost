@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("The picture on an Outpost", .serialized)
struct OutpostPhotoSharingTests {
    private static let photo = Data(repeating: 0xAB, count: 4_000)
    private static let wallPhoto = Data(repeating: 0x2C, count: 3_500)

    private func wallOnly() async throws -> (bob: AppSession, carol: AppSession, mailbox: InMemoryMailbox) {
        let mailbox = InMemoryMailbox()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for s in [bob, carol] { await s.load() }
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")
        try await bob.allowOutpost(try #require(carol.enrolment?.identity.id), everything: true)
        await carol.setShowsOthersAvatars(true)
        try await settle([bob, carol], mailbox)
        return (bob, carol, mailbox)
    }

    private func roomAndWall() async throws -> (bob: AppSession, carol: AppSession, mailbox: InMemoryMailbox) {
        let mailbox = InMemoryMailbox()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for s in [bob, carol] { await s.load() }
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")
        let room = try await bob.createRoom(named: "Lanterns")
        let invite = try await bob.invite(joinerCode: carol.identityCode(), joining: room, mailbox: nil)
        try await carol.redeem(inviteCode: try invite.encoded())
        try await bob.sync(through: mailbox)
        try await carol.accept(
            invite.attestation, from: try #require(bob.enrolment?.identity.publicKeys))
        try await bob.allowOutpost(try #require(carol.enrolment?.identity.id), everything: true)
        await carol.setShowsOthersAvatars(true)
        try await settle([bob, carol], mailbox)
        return (bob, carol, mailbox)
    }

    private func settle(_ everyone: [AppSession], _ mailbox: InMemoryMailbox, rounds: Int = 6) async throws {
        for _ in 0..<rounds {
            for s in everyone { try await s.sync(through: mailbox, media: mailbox) }
        }
    }

    @Test("With Share my photo off, nothing is uploaded and nothing is announced")
    func sharingIsTheGate() async throws {
        let (bob, carol, mailbox) = try await wallOnly()
        #expect(bob.showsPhotoOnOutpost, "on by default")

        try await bob.shareOutpostPhoto(Self.wallPhoto, through: mailbox)
        try await settle([bob, carol], mailbox)

        #expect(await mailbox.storedAttachmentCount == 0)
        #expect(bob.ownOutpostPhotoReference == nil)
        let bobID = try #require(bob.enrolment?.identity.id)
        #expect(carol.sharedOutpostPhotoReference(of: bobID) == nil)
    }

    @Test("With the Outpost switch off, nothing reaches the wall")
    func theWallSwitchIsSeparate() async throws {
        let (bob, carol, mailbox) = try await wallOnly()
        await bob.setSharesAvatar(true)
        await bob.setShowsPhotoOnOutpost(false)

        try await bob.shareOutpostPhoto(Self.photo, through: mailbox)
        try await settle([bob, carol], mailbox)

        #expect(bob.ownOutpostPhotoReference == nil)
        #expect(await mailbox.storedAttachmentCount == 0)
    }

    @Test("A member in no rooms still has a picture on their Outpost")
    func noRoomsIsStillAWall() async throws {
        let (bob, carol, mailbox) = try await wallOnly()
        await bob.setSharesAvatar(true)

        try await bob.sharePhoto(Self.photo, through: mailbox)
        #expect(bob.ownPhotoReference == nil, "no rooms means no rooms pointer")

        try await bob.shareOutpostPhoto(Self.photo, through: mailbox)
        try await settle([bob, carol], mailbox)
        #expect(bob.ownOutpostPhotoReference != nil)
    }

    @Test("A picture on the wall reaches a reader with no rooms photo to fall back on")
    func theWallCarriesItAlone() async throws {
        let (bob, carol, mailbox) = try await roomAndWall()
        let bobID = try #require(bob.enrolment?.identity.id)
        await bob.setSharesAvatar(true)

        try await bob.shareOutpostPhoto(Self.photo, through: mailbox)
        try await settle([bob, carol], mailbox)

        #expect(carol.sharedPhotoReference(of: bobID) == nil, "no rooms photo to fall back on")
        let reference = try #require(
            carol.sharedOutpostPhotoReference(of: bobID), "the wall's pointer did not reach Carol")
        let bytes = try await carol.downloadSharedPhoto(reference, from: bobID, through: mailbox)
        #expect(bytes == Self.photo)
    }

    @Test("The wall's record is its own, not the rooms'")
    func theWallKeepsItsOwnRecord() async throws {
        let (bob, _, mailbox) = try await roomAndWall()
        await bob.setSharesAvatar(true)

        try await bob.sharePhoto(Self.photo, through: mailbox)
        try await bob.shareOutpostPhoto(Self.photo, through: mailbox)

        #expect(bob.ownPhotoReference != nil)
        #expect(bob.ownOutpostPhotoReference != nil)
        #expect(bob.ownOutpostPhotoReference?.id != bob.ownPhotoReference?.id)
        #expect(await mailbox.storedAttachmentCount == 2)
    }

    @Test("A picture chosen for the wall does not become the face the rooms see")
    func aWallPictureStaysOnTheWall() async throws {
        let (bob, carol, mailbox) = try await roomAndWall()
        let bobID = try #require(bob.enrolment?.identity.id)
        await bob.setSharesAvatar(true)

        try await bob.sharePhoto(Self.photo, through: mailbox)
        try await bob.shareOutpostPhoto(Self.wallPhoto, through: mailbox)
        try await settle([bob, carol], mailbox)

        let wall = try #require(bob.ownOutpostPhotoReference)
        let rooms = try #require(bob.ownPhotoReference)
        #expect(wall.id != rooms.id)

        #expect(carol.sharedOutpostPhotoReference(of: bobID)?.id == wall.id)
        let bytes = try await carol.downloadSharedPhoto(
            try #require(carol.sharedOutpostPhotoReference(of: bobID)), from: bobID, through: mailbox)
        #expect(bytes == Self.wallPhoto)
    }

    @Test("Changing the photo on You does not delete what the wall names")
    func changingTheOwnPhotoLeavesTheWallAlone() async throws {
        let (bob, carol, mailbox) = try await roomAndWall()
        let bobID = try #require(bob.enrolment?.identity.id)
        await bob.setSharesAvatar(true)

        try await bob.sharePhoto(Self.photo, through: mailbox)
        try await bob.shareOutpostPhoto(Self.wallPhoto, through: mailbox)
        let wall = try #require(bob.ownOutpostPhotoReference)
        try await settle([bob, carol], mailbox)

        try await bob.sharePhoto(Data(repeating: 0x77, count: 2_500), through: mailbox)
        try await settle([bob, carol], mailbox)

        #expect(bob.ownOutpostPhotoReference?.id == wall.id, "the wall's pointer moved")
        let bytes = try await carol.downloadSharedPhoto(wall, from: bobID, through: mailbox)
        #expect(bytes == Self.wallPhoto, "the wall's record was deleted with the old photo")
    }

    @Test("The wall's picture is never the answer for a room")
    func theTwoPointersStayApart() async throws {
        let (bob, carol, mailbox) = try await roomAndWall()
        let bobID = try #require(bob.enrolment?.identity.id)
        await bob.setSharesAvatar(true)

        try await bob.sharePhoto(Self.photo, through: mailbox)
        try await bob.shareOutpostPhoto(Self.wallPhoto, through: mailbox)
        try await settle([bob, carol], mailbox)

        let rooms = try #require(carol.sharedPhotoReference(of: bobID))
        let wall = try #require(carol.sharedOutpostPhotoReference(of: bobID))
        #expect(rooms.id != wall.id)
        #expect(try await carol.downloadSharedPhoto(rooms, from: bobID, through: mailbox) == Self.photo)
    }

    @Test("Taking the photo down takes the wall's with it")
    func withdrawingTakesBoth() async throws {
        let (bob, carol, mailbox) = try await roomAndWall()
        await bob.setSharesAvatar(true)
        try await bob.sharePhoto(Self.photo, through: mailbox)
        try await bob.shareOutpostPhoto(Self.wallPhoto, through: mailbox)
        try await settle([bob, carol], mailbox)

        await bob.withdrawPhoto(through: mailbox)
        try await settle([bob, carol], mailbox)

        #expect(bob.ownPhotoReference == nil)
        #expect(bob.ownOutpostPhotoReference == nil)
        #expect(await mailbox.storedAttachmentCount == 0)
    }
}
