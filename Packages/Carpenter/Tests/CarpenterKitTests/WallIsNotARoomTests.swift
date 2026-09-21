import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("What a wall is not told", .serialized)
struct WallIsNotARoomTests {
    private func triangle() async throws -> (
        alice: AppSession, bob: AppSession, carol: AppSession, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for s in [alice, bob, carol] { await s.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")
        try await introduce(bob, to: alice, named: "Lanterns", through: mailbox)
        try await introduce(bob, to: carol, named: "Kites", through: mailbox)
        try await bob.allowOutpost(try #require(alice.enrolment?.identity.id), everything: true)
        try await bob.allowOutpost(try #require(carol.enrolment?.identity.id), everything: true)
        try await settle([alice, bob, carol], through: mailbox)
        return (alice, bob, carol, mailbox)
    }

    private func introduce(
        _ host: AppSession, to guest: AppSession, named name: String,
        through mailbox: InMemoryMailbox
    ) async throws {
        let room = try await host.createRoom(named: name)
        let invite = try await host.invite(joinerCode: guest.identityCode(), joining: room, mailbox: nil)
        try await guest.redeem(inviteCode: try invite.encoded())
        try await host.sync(through: mailbox)
        try await guest.accept(
            invite.attestation, from: try #require(host.enrolment?.identity.publicKeys))
        try await settle([host, guest], through: mailbox)
    }

    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for s in everyone { try await s.sync(through: mailbox, media: mailbox) }
        }
    }

    @Test("Your silence is not announced onto somebody else's Outpost")
    func focusStaysOutOfWalls() async throws {
        let (alice, bob, carol, mailbox) = try await triangle()
        await alice.setFocusSharing(FocusSharing(sharesFocus: true))
        await carol.setFocusSharing(FocusSharing(showsOthersFocus: true))
        await alice.reportFocus(silenced: true)
        try await settle([alice, bob, carol], through: mailbox)

        let aliceID = try #require(alice.enrolment?.identity.id)
        #expect(
            carol.focusStatus(of: aliceID) == nil,
            "a stranger on the same wall was told when Alice put her phone down")
    }

    @Test("Your photo is not announced onto somebody else's Outpost")
    func photosStayOutOfWalls() async throws {
        let (alice, bob, carol, mailbox) = try await triangle()
        let bobWall = ConversationID.outpost(of: try #require(bob.enrolment?.identity.id))
        let aliceID = try #require(alice.enrolment?.identity.id)

        await alice.setSharesAvatar(true)
        try await alice.sharePhoto(Data(repeating: 0xAB, count: 4_000), through: mailbox)
        try await settle([alice, bob, carol], through: mailbox)

        #expect(
            alice.announcedPhoto(of: aliceID, in: bobWall) == nil,
            "Alice's photo was announced onto a wall she is only a reader of")
    }

    @Test("Your name is not announced onto somebody else's Outpost")
    func namesStayOutOfWalls() async throws {
        let (alice, bob, carol, mailbox) = try await triangle()
        let bobWall = ConversationID.outpost(of: try #require(bob.enrolment?.identity.id))
        let aliceID = try #require(alice.enrolment?.identity.id)

        await alice.setSharesName(true)
        try await settle([alice, bob, carol], through: mailbox)

        #expect(
            alice.announcedName(of: aliceID, in: bobWall) == nil,
            "Alice's name was announced onto a wall she is only a reader of")
    }

    @Test("Being let in to somebody's Outpost says nothing about you on it")
    func beingLetInSaysNothing() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        for s in [alice, bob] { await s.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await introduce(bob, to: alice, named: "Lanterns", through: mailbox)

        await alice.setSharesName(true)
        await alice.setSharesAvatar(true)
        await alice.setFocusSharing(FocusSharing(sharesFocus: true))
        try await alice.sharePhoto(Data(repeating: 0xAB, count: 4_000), through: mailbox)
        await alice.reportFocus(silenced: true)
        try await settle([alice, bob], through: mailbox)

        try await bob.allowOutpost(try #require(alice.enrolment?.identity.id), everything: true)
        try await settle([alice, bob], through: mailbox)

        let bobWall = ConversationID.outpost(of: try #require(bob.enrolment?.identity.id))
        let aliceID = try #require(alice.enrolment?.identity.id)
        #expect(
            alice.announcedName(of: aliceID, in: bobWall) == nil,
            "Alice's name landed on the wall she was let into")
        #expect(
            alice.announcedPhoto(of: aliceID, in: bobWall) == nil,
            "Alice's photo landed on the wall she was let into")
        #expect(
            alice.lastFocusStatus(of: aliceID, in: bobWall) == nil,
            "Alice's Do Not Disturb landed on the wall she was let into")
    }

    @Test("A room you are in is still told")
    func roomsAreStillTold() async throws {
        let (alice, bob, _, mailbox) = try await triangle()
        let aliceID = try #require(alice.enrolment?.identity.id)
        await alice.setSharesName(true)
        await alice.setFocusSharing(FocusSharing(sharesFocus: true))
        await bob.setShowsOthersNames(true)
        await bob.setFocusSharing(FocusSharing(showsOthersFocus: true))
        await alice.reportFocus(silenced: true)
        try await settle([alice, bob], through: mailbox)

        #expect(bob.member(aliceID).displayName == "Alice")
        #expect(bob.focusStatus(of: aliceID)?.silenced == true)
    }
}
