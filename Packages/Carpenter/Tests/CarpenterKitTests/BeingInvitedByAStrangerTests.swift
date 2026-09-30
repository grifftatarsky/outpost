@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Somebody a phone has only heard of can still invite it into a room", .serialized)
struct BeingInvitedByAStrangerTests {
    @MainActor
    private struct FriendOfAFriend {
        let three: RoomOfThree
        let dave: AppSession

        var daveID: ParticipantID { dave.enrolment!.identity.id }

        static func make() async throws -> FriendOfAFriend {
            let three = try await RoomOfThree.make()
            let dave = TestSession.make()
            await dave.load()
            try await dave.createIdentity(displayName: "Dave")
            let kitchen = try await three.alice.createRoom(named: "Kitchen")
            try await join(dave, into: kitchen, of: three.alice, through: three.mailbox)
            for _ in 0..<3 {
                for session in [three.alice, three.carol, three.sam, dave] {
                    try await session.sync(through: three.mailbox, media: three.mailbox)
                }
            }
            try #require(dave.replica.registry(for: three.carolID) != nil, "precondition: Dave's phone has heard of Carol")
            try #require(dave.roster(of: three.room).members.isEmpty, "precondition: Dave is not in the Lanterns room")
            return FriendOfAFriend(three: three, dave: dave)
        }
    }

    @Test("Carol invites her friend's friend, who has never met her, and he gets into the room")
    func aFriendOfAFriendGetsIn() async throws {
        let t = try await FriendOfAFriend.make()

        try await join(t.dave, into: t.three.room, of: t.three.carol, through: t.three.mailbox)

        #expect(
            t.dave.roster(of: t.three.room).members.contains(t.daveID),
            "Dave never got into the room Carol invited him to")
        #expect(t.three.carol.roster(of: t.three.room).members.contains(t.daveID))
        #expect(t.dave.chains[t.three.room] != nil, "Dave got in without a key to read the room")
    }

    @Test("A phone makes a space for the one person it has met, not for everybody its inviter knows")
    func aSpaceOnlyForWhoItHasMet() async throws {
        let t = try await FriendOfAFriend.make()

        try #require(t.dave.replica.registry(for: t.three.samID) != nil, "precondition: Dave's phone has heard of Sam")
        let spaces = await t.three.mailbox.spaceCount(of: t.daveID)
        #expect(spaces == 2, "Dave's phone made a space in his iCloud for somebody he has never met")
    }
}
