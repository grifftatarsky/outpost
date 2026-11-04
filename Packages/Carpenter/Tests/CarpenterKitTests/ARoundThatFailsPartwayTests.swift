@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A round that fails partway keeps what arrived", .serialized)
struct ARoundThatFailsPartwayTests {
    private func joined(_ guests: [String]) async throws -> (
        host: AppSession, guests: [AppSession], room: RoomID, mailbox: HookedMailbox
    ) {
        let mailbox = HookedMailbox()
        let host = TestSession.make()
        await host.load()
        try await host.createIdentity(displayName: "Carol")
        let room = try await host.createRoom(named: "Darkroom")
        var joined: [AppSession] = []
        for name in guests {
            let guest = TestSession.make()
            await guest.load()
            try await guest.createIdentity(displayName: name)
            let invite = try await host.invite(
                joinerCode: await guest.joinerCode(through: mailbox), joining: room, through: mailbox)
            try await guest.redeem(inviteCode: try invite.encoded())
            for _ in 0..<5 {
                try await host.sync(through: mailbox, media: mailbox.inner)
                try await guest.sync(through: mailbox, media: mailbox.inner)
            }
            joined.append(guest)
        }
        for _ in 0..<3 {
            for session in [host] + joined { try await session.sync(through: mailbox, media: mailbox.inner) }
        }
        try #require(host.roster(of: room).members.count == guests.count + 1, "precondition: everybody is in")
        return (host, joined, room, mailbox)
    }

    @Test("A photo that arrived in a round whose send failed is still collected")
    func aPhotoIsCollectedThoughTheSendFailed() async throws {
        let (carol, guests, room, mailbox) = try await joined(["Bob"])
        let bob = guests[0]
        try await carol.send(SendingPhotoTests.photo(), to: room, through: mailbox.inner)
        try await carol.sync(through: mailbox, media: mailbox.inner)

        try await bob.send("waiting to go", to: room)
        await mailbox.refuse(.noRoomInICloud)
        await #expect(throws: MailboxFailure.noRoomInICloud) {
            try await bob.sync(through: mailbox, media: mailbox.inner)
        }
        let photo = try #require(bob.messages(in: room).last { $0.media != nil }?.media, "precondition: the entry arrived")
        #expect(bob.cannotSend == .noRoomInICloud, "the round kept going and forgot to say why nothing went")
        #expect(await bob.holdsAttachment(photo.id), "the send failed and the round never reached the photo")

        await mailbox.relent()
        try await bob.sync(through: mailbox, media: mailbox.inner)
        #expect(await bob.holdsAttachment(photo.id), "the photo was never noted, so no later round collected it")
    }

    @Test("One person whose mail cannot be read does not stop the round for everybody else")
    func oneFetchFailureLeavesTheRestOfTheRound() async throws {
        let (carol, guests, room, mailbox) = try await joined(["Bob", "Dave"])
        let (bob, dave) = (guests[0], guests[1])
        try await dave.send("from Dave", to: room)
        try await dave.sync(through: mailbox, media: mailbox.inner)
        try await carol.send("from Carol", to: room)

        await mailbox.cannotCollect(from: bob.enrolment!.identity.id)
        await #expect(throws: MailboxError.unavailable) {
            try await carol.sync(through: mailbox, media: mailbox.inner)
        }
        #expect(carol.messages(in: room).contains { $0.body == "from Dave" }, "Bob's failure stopped Carol reading Dave")

        await mailbox.collectsFromEveryone()
        try await dave.sync(through: mailbox, media: mailbox.inner)
        #expect(
            dave.messages(in: room).contains { $0.body == "from Carol" },
            "one person's mail would not open, and Carol's own message never left")
    }
}
