@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Acknowledging a round", .serialized)
struct RoundAcknowledgementTests {
    private func joined() async throws -> (
        alice: AppSession, bob: AppSession, room: RoomID, mailbox: InMemoryMailbox
    ) {
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
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, room, mailbox)
    }

    @Test("A packet somebody else deleted before it was signed for is sent again, and the rest are taken back")
    func vanishedPacketIsSentAgain() async throws {
        let (alice, bob, room, mailbox) = try await joined()

        for word in ["first", "second", "third"] {
            try await alice.send(word, to: room)
            try await alice.sync(through: mailbox)
        }
        let written = await mailbox.writtenPackets.suffix(3)
        #expect(written.count == 3, "precondition: three packets were written")

        await mailbox.delete(packet: written[written.startIndex + 1])

        try await bob.sync(through: mailbox)
        var bobs = bob.messages(in: room).map(\.body)
        #expect(bobs.contains("first") && bobs.contains("third"), "the surviving packets were read")
        #expect(!bobs.contains("second"), "precondition: the deleted packet never reached Bob")

        try await alice.sync(through: mailbox)
        let left = try await mailbox.sentPackets()
        #expect(
            written.filter { left.keys.contains($0) }.isEmpty,
            "a packet Bob signed for was left in Alice's outbox")

        try await bob.sync(through: mailbox)
        bobs = bob.messages(in: room).map(\.body)
        #expect(bobs.contains("second"), "a message whose packet was deleted before Bob signed for it never came back")
    }

    @Test("A packet whose entries could not be written down is not acknowledged")
    func aRefusedWriteLeavesThePacketOutstanding() async throws {
        let mailbox = InMemoryMailbox()
        let log = MemoryLogStore()
        let alice = TestSession.make()
        let bob = AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(), log: log,
                documents: FileDocumentStore(
                    url: TestScratch.root.appending(path: "carpenter-test-\(UUID().uuidString)")),
                media: MemoryMediaStore()),
            clock: TestClock(now: TestSession.now))
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        try await alice.send("the lanterns are lit", to: room)
        try await alice.sync(through: mailbox)
        let packet = try #require(await mailbox.writtenPackets.last)

        await log.refuse(true)
        await #expect(throws: (any Error).self) { try await bob.sync(through: mailbox) }

        let outstanding = try await mailbox.sentPackets()
        #expect(
            outstanding[packet]?.receipts.isEmpty == true,
            "a packet was signed for whose entries never reached the disk")

        await log.refuse(false)
        try await bob.sync(through: mailbox)
        let arrived = try #require(
            bob.messages(in: room).first { $0.body == "the lanterns are lit" })
        #expect(await log.stored.contains { $0.hash == arrived.id.entry })
    }

    @Test("The failure names what it could not acknowledge, and how much it could")
    func failureNamesThePackets() {
        let stuck = PacketID(rawValue: UUID(uuidString: "0BADCAFE-0000-4000-8000-000000000000")!)
        let failure = AcknowledgementFailure(failed: [stuck: "unknownPacket"], acknowledged: 23)
        let said = failure.description
        #expect(said.hasPrefix("1 of 24 packet(s) not acknowledged"), Comment(rawValue: said))
        #expect(said.contains("0BADCAFE: unknownPacket"), Comment(rawValue: said))
    }
}
