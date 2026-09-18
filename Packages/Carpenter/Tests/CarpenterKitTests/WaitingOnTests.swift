@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Which people a room is waiting on, and what was last heard from them", .serialized)
struct WaitingOnTests {
    @Test("Somebody who has not collected is named, and stops being named once they have")
    func waitingThenHolding() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: room, of: alice, through: mailbox)
        let bobID = try #require(bob.enrolment?.identity.id)

        try await alice.send("are you there", to: room)
        #expect(
            alice.waitingOn(in: room).first?.holding == .missing(1),
            "a message that has not left this phone is missing for everybody, round or no round")

        try await alice.sync(through: mailbox)
        let waiting = try #require(alice.waitingOn(in: room).first)
        #expect(waiting.member.id == bobID)
        #expect(waiting.holding == .missing(1), "Bob has not collected, and nothing said so")
        #expect(waiting.lastHeard == nil, "Bob has written nothing, so nothing has been heard")
        #expect(
            alice.messages(in: room).last?.delivery == .sent,
            "the mark and the list must agree: nobody has it")

        try await bob.sync(through: mailbox)
        try await bob.send("here", to: room)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        #expect(alice.waitingOn(in: room).first?.holding == .everything)
        #expect(alice.waitingOn(in: room).first?.lastHeard != nil, "Bob wrote, and it was not heard")
        #expect(alice.messages(in: room).last(where: \.isMine)?.delivery.isCollected == true)
    }

    @Test("Before this device has asked the mailbox, it says so rather than guessing")
    func notCheckedYet() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: room, of: alice, through: mailbox)

        let relaunched = alice
        relaunched.pendingRecipients = nil
        #expect(relaunched.waitingOn(in: room).first?.holding == .notCheckedYet)
        #expect(relaunched.waitingOn(in: room).allSatisfy { $0.member.id != alice.enrolment?.identity.id })
    }
}
