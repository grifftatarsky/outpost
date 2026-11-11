@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A message is written after this phone has collected what iCloud holds", .serialized, .tags(.membership))
struct AMessageWaitsForWhatICloudHoldsTests {
    @MainActor private struct World {
        let alice: AppSession
        let bob: AppSession
        let carol: AppSession
        let mailbox: HookedMailbox
        let room: RoomID

        var bobID: ParticipantID { get throws { try #require(bob.enrolment?.identity.id) } }
        var carolID: ParticipantID { get throws { try #require(carol.enrolment?.identity.id) } }

        func settle() async throws {
            for _ in 0..<4 {
                for session in [alice, bob, carol] { _ = try? await session.sync(through: mailbox) }
            }
        }

        var keyBobLastWroteUnder: EpochNumber? {
            let me = bob.enrolment?.identity.id
            return bob.replica.allEntries.filter { $0.author == me && $0.room == room }
                .max { $0.seq < $1.seq }?.payload.epoch
        }
    }

    private func threeInARoom() async throws -> World {
        let (alice, bob, carol) = (TestSession.make(), TestSession.make(), TestSession.make())
        let mailbox = HookedMailbox()
        for (session, name) in [(alice, "Alice"), (bob, "Bob"), (carol, "Carol")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        let room = try await alice.createRoom(named: "Lanterns")
        let world = World(alice: alice, bob: bob, carol: carol, mailbox: mailbox, room: room)
        for joiner in [bob, carol] {
            let invite = try await alice.invite(
                joinerCode: await joiner.joinerCode(through: mailbox), joining: room, through: mailbox)
            try await joiner.redeem(inviteCode: try invite.encoded())
            try await world.settle()
        }
        #expect(alice.roster(of: room).members.count == 3)
        #expect(bob.roster(of: room).members.count == 3)
        return world
    }

    @Test("A removal that reached iCloud is applied before the message is sealed, so it goes out under a key the removed person never held")
    func aRemovalInICloudChangesTheKeyFirst() async throws {
        let world = try await threeInARoom()
        try await world.bob.send("before", to: world.room)
        let old = try #require(world.keyBobLastWroteUnder)

        try await world.alice.remove(try world.carolID, from: world.room)
        try await world.alice.sync(through: world.mailbox)
        #expect(world.bob.roster(of: world.room).members.contains(try world.carolID), "precondition: Bob has not heard")

        try await world.bob.send("after the removal", to: world.room, after: world.mailbox)

        #expect(!world.bob.roster(of: world.room).members.contains(try world.carolID))
        #expect(try #require(world.keyBobLastWroteUnder) > old, "the message was sealed under a key Carol holds")
        try await world.settle()
        #expect(world.alice.messages(in: world.room).contains { $0.body == "after the removal" })
        #expect(!world.carol.messages(in: world.room).contains { $0.body == "after the removal" })
    }

    @Test("Without the fetch the same message is sealed under the key the removed person holds")
    func withoutTheFetchTheOldKeyIsUsed() async throws {
        let world = try await threeInARoom()
        try await world.bob.send("before", to: world.room)
        let old = try #require(world.keyBobLastWroteUnder)
        try await world.alice.remove(try world.carolID, from: world.room)
        try await world.alice.sync(through: world.mailbox)

        try await world.bob.send("after the removal", to: world.room)

        #expect(world.keyBobLastWroteUnder == old)
    }

    @Test("A member who finds in that fetch that they were removed writes nothing")
    func aRemovedMemberWritesNothing() async throws {
        let world = try await threeInARoom()
        try await world.alice.remove(try world.bobID, from: world.room)
        try await world.alice.sync(through: world.mailbox)
        let before = world.bob.head?.hash

        await #expect(throws: MembershipError.removedFromThisRoom) {
            try await world.bob.send("am I still here", to: world.room, after: world.mailbox)
        }
        #expect(world.bob.head?.hash == before)
    }

    @Test("When iCloud does not answer, the message is still written and waits to go out")
    func whenICloudDoesNotAnswerTheMessageIsKept() async throws {
        let world = try await threeInARoom()
        await world.mailbox.cannotCollect(from: try #require(world.alice.enrolment?.identity.id))
        await world.mailbox.cannotCollect(from: try world.carolID)

        try await world.bob.send("written offline", to: world.room, after: world.mailbox)

        #expect(world.bob.messages(in: world.room).contains { $0.body == "written offline" })
        #expect(world.bob.roomsWithUnsentMessages.contains(world.room))
        await world.mailbox.collectsFromEveryone()
        try await world.settle()
        #expect(world.alice.messages(in: world.room).contains { $0.body == "written offline" })
    }

    @Test("The fetch reads only from the people in the room")
    func onlyTheRoomsMembersAreRead() async throws {
        let world = try await threeInARoom()
        let solo = try await world.alice.createRoom(named: "Just us")
        let invite = try await world.alice.invite(
            joinerCode: await world.bob.joinerCode(through: world.mailbox), joining: solo, through: world.mailbox)
        try await world.bob.redeem(inviteCode: try invite.encoded())
        try await world.settle()
        await world.mailbox.cannotCollect(from: try world.carolID)

        await #expect(throws: (any Error).self, "precondition: reading from everybody reaches Carol and fails") {
            try await world.alice.sync(through: world.mailbox, mode: .readOnly)
        }
        try await world.alice.sync(
            through: world.mailbox, mode: .readOnly, from: world.alice.roster(of: solo).members)
    }
}
