import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@MainActor
@Suite("What a repair answer is allowed to hand over", .serialized)
struct RepairScopeTests {
    private func settle(_ sessions: [AppSession], _ mailbox: InMemoryMailbox, rounds: Int = 8) async throws {
        for _ in 0..<rounds {
            for session in sessions { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func heldRooms(_ session: AppSession) -> Set<RoomID> {
        Set(session.replica.allEntries.compactMap(\.room))
    }

    @Test("A member never receives entries from a room they are not in")
    func roomsAreNotShared() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for session in [alice, bob, carol] { await session.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")

        let shared = try await alice.createRoom(named: "Hangar 7")
        let apart = try await alice.createRoom(named: "Somewhere else")

        let toBob = try await alice.invite(joinerCode: bob.identityCode(), joining: shared, mailbox: nil)
        try await bob.redeem(inviteCode: try toBob.encoded())
        let toCarol = try await alice.invite(joinerCode: carol.identityCode(), joining: apart, mailbox: nil)
        try await carol.redeem(inviteCode: try toCarol.encoded())
        try await settle([alice, bob, carol], mailbox)

        try await alice.send("for bob", to: shared)
        try await alice.send("for carol", to: apart)
        try await settle([alice, bob, carol], mailbox)

        #expect(!heldRooms(bob).contains(apart), "bob holds entries from a room he is not in")
        #expect(!heldRooms(carol).contains(shared), "carol holds entries from a room she is not in")
    }

    @Test("A member invited from today never receives what was said before")
    func floorIsNotOnlyADrawingRule() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        for session in [alice, bob] { await session.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("before bob", to: room)

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil, sharingHistory: false)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await settle([alice, bob], mailbox)
        try await alice.send("after bob", to: room)
        try await settle([alice, bob], mailbox)

        let bobID = try #require(bob.enrolment?.identity.id)
        let floor = try #require(alice.roster(of: room).historyFloor(of: bobID))
        let early = bob.replica.allEntries.filter { $0.room == room && $0.payload.epoch < floor }
        #expect(early.isEmpty, "bob holds \(early.count) sealed entr(ies) from before he was let in")
    }

    @Test("A room with no repair still knows what it is missing")
    func gapsAfterScoping() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for session in [alice, bob, carol] { await session.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")

        let shared = try await alice.createRoom(named: "Hangar 7")
        let apart = try await alice.createRoom(named: "Somewhere else")
        let toBob = try await alice.invite(joinerCode: bob.identityCode(), joining: shared, mailbox: nil)
        try await bob.redeem(inviteCode: try toBob.encoded())
        let toCarol = try await alice.invite(joinerCode: carol.identityCode(), joining: apart, mailbox: nil)
        try await carol.redeem(inviteCode: try toCarol.encoded())
        try await settle([alice, bob, carol], mailbox)

        for index in 1...3 { try await alice.send("apart \(index)", to: apart) }
        try await alice.send("shared", to: shared)
        try await settle([alice, bob, carol], mailbox)

        #expect(
            bob.missingHistory(in: shared).isEmpty,
            "bob is asking forever for positions that belong to another room")
    }
}
