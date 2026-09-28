import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp
@testable import CarpenterKit

@Suite("A message too big to send", .serialized)
@MainActor
struct AMessageTooBigTests {
    private func joined() async throws -> (alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox, room: RoomID) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: await bob.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, mailbox, room)
    }

    @Test("A message too big to send is refused before it is written")
    func anOversizedMessageIsRefused() async throws {
        let (alice, _, _, room) = try await joined()
        let before = alice.replica.entryCount

        await #expect(throws: AppSessionError.tooBigToSend) {
            try await alice.send(String(repeating: "a", count: 900_000), to: room)
        }
        #expect(alice.replica.entryCount == before, "the refused message went into the log anyway")
    }

    @Test("An entry already too big for any packet does not stop everything said after it")
    func anOversizedEntryDoesNotBlockTheRest() async throws {
        let (alice, bob, mailbox, room) = try await joined()
        let enrolment = try #require(alice.enrolment)
        let chain = try #require(alice.chains[room])
        let oversized = try Entry.append(
            after: alice.head, author: enrolment.identity.id, device: enrolment.device,
            clock: alice.replica.frontier, wallTime: TestSession.now, room: room,
            payload: try Payload.post(String(repeating: "a", count: 900_000)),
            at: chain.highestKnownEpoch ?? .initial, sealedWith: chain)
        try alice.replica.integrate(oversized)
        alice.head = oversized.link

        try await alice.send("hello after", to: room)
        for _ in 0..<3 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(
            bob.messages(in: room).contains { $0.body == "hello after" },
            "an entry too big for the mailbox sat at the head of the queue and nothing behind it was ever sent")
    }
}
