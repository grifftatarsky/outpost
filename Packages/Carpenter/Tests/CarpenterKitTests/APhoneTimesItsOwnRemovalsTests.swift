@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A phone writes down when it made a removal of its own", .serialized, .tags(.membership))
struct APhoneTimesItsOwnRemovalsTests {
    private func roomOfTwo() async throws -> (alice: AppSession, bob: AppSession, room: RoomID) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        for (session, name) in [(alice, "Alice"), (bob, "Bob")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(
            joinerCode: await bob.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, room)
    }

    @Test("Removing somebody leaves a time for that removal on the remover's phone")
    func aRemovalIsTimed() async throws {
        let (alice, bob, room) = try await roomOfTwo()
        let before = alice.persisted.claimTimes

        try await alice.remove(try #require(bob.enrolment?.identity.id), from: room)

        let added = alice.persisted.claimTimes.filter { before[$0.key] == nil }
        #expect(added.count == 1)
        #expect(added.values.allSatisfy { time in before.values.allSatisfy { $0 < time } }, "timed before something already seen")
    }

    @Test("Leaving leaves a time for that departure on the leaver's phone")
    func aDepartureIsTimed() async throws {
        let (_, bob, room) = try await roomOfTwo()
        let before = bob.persisted.claimTimes

        try await bob.leave(room)

        #expect(bob.persisted.claimTimes.count == before.count + 1)
    }
}
