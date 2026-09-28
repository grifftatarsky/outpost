@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A packet holds one reader, and one changed after it was written is sent again", .serialized)
struct TamperedPacketTests {
    private struct Three {
        let alice: AppSession
        let bob: AppSession
        let carol: AppSession
        let room: RoomID
        let mailbox: InMemoryMailbox
    }

    private func three() async throws -> Three {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for (session, name) in [(alice, "Alice"), (bob, "Bob"), (carol, "Carol")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        let room = try await alice.createRoom(named: "Lanterns")
        try await join(bob, into: room, of: alice, through: mailbox)
        try await join(carol, into: room, of: alice, through: mailbox)
        for _ in 0..<3 {
            for session in [alice, bob, carol] { try await session.sync(through: mailbox) }
        }
        try #require(alice.roster(of: room).members.count == 3, "precondition: three members")
        return Three(alice: alice, bob: bob, carol: carol, room: room, mailbox: mailbox)
    }


    @Test("A message for two people goes as a packet for each, in each one's own space, sealed for that one alone")
    func eachPacketHoldsOneReader() async throws {
        let three = try await three()
        let before = Set(await three.mailbox.writtenPackets)
        try await three.alice.send("for both of you", to: three.room)
        try await three.alice.sync(through: three.mailbox)

        let written = await three.mailbox.writtenPackets.filter { !before.contains($0) }
        let sent = await three.mailbox.everySentPacket
        let readers = written.compactMap { sent[$0] }
        #expect(readers.count >= 2, "precondition: the round wrote for both")
        #expect(readers.allSatisfy { $0.recipients.count == 1 }, "a packet could be opened by more than one person")
        #expect(
            Set(readers.map(\.to)) == Set([three.bob, three.carol].compactMap { $0.enrolment?.identity.id }),
            "the packets were not one for each reader")
    }

    @Test("A packet changed on the server after it was written is sent again")
    func alteredPacketIsSentAgain() async throws {
        let three = try await three()
        let before = Set(await three.mailbox.writtenPackets)
        try await three.alice.send("untouched", to: three.room)
        try await three.alice.sync(through: three.mailbox)
        for packet in await three.mailbox.writtenPackets where !before.contains(packet) {
            await three.mailbox.tamper(packet: packet) { fields in
                guard case .data(var sealed)? = fields[PacketWire.ciphertext], !sealed.isEmpty else { return }
                sealed[sealed.startIndex] ^= 0xFF
                fields[PacketWire.ciphertext] = .data(sealed)
            }
        }
        try await three.carol.sync(through: three.mailbox)
        #expect(
            !three.carol.messages(in: three.room).contains { $0.body == "untouched" },
            "precondition: the altered packet could not be read")

        for _ in 0..<2 {
            try await three.alice.sync(through: three.mailbox)
            try await three.carol.sync(through: three.mailbox)
        }
        #expect(
            three.carol.messages(in: three.room).contains { $0.body == "untouched" },
            "a packet altered in the outbox was never sent again")
    }

    @Test("A packet's content digest ignores the order it was built in and an empty grant list, and nothing else")
    func digestIsStable() throws {
        let one = RecipientTag(rawValue: Data([1]))
        let two = RecipientTag(rawValue: Data([2]))
        let id = PacketID()
        let written = SyncPacket(
            id: id, wraps: [one: Data([9]), two: Data([8])], ciphertext: Data([7, 7]),
            grants: [one: [Data([3]), Data([4])], two: []])
        let read = try #require(PacketWire.packet(from: PacketWire.fields(of: written)))
        #expect(read.contentDigest == written.contentDigest, "a packet read back reads as altered")
        let stripped = SyncPacket(id: id, wraps: [one: Data([9])], ciphertext: Data([7, 7]), grants: written.grants)
        #expect(stripped.contentDigest != written.contentDigest, "dropping a recipient went unnoticed")
        let flipped = SyncPacket(id: id, wraps: written.wraps, ciphertext: Data([7, 6]), grants: written.grants)
        #expect(flipped.contentDigest != written.contentDigest, "changing the sealed words went unnoticed")
        let regranted = SyncPacket(
            id: id, wraps: written.wraps, ciphertext: Data([7, 7]), grants: [one: [Data([3])], two: []])
        #expect(regranted.contentDigest != written.contentDigest, "dropping a room key went unnoticed")
    }

    @Test("A packet nobody touched is not sent twice")
    func untouchedIsNotResent() async throws {
        let three = try await three()
        try await three.alice.send("once", to: three.room)
        for _ in 0..<3 {
            for session in [three.alice, three.bob, three.carol] { try await session.sync(through: three.mailbox) }
        }
        #expect(three.carol.messages(in: three.room).filter { $0.body == "once" }.count == 1)
        #expect(three.bob.messages(in: three.room).filter { $0.body == "once" }.count == 1)
        let resent = try await three.alice.sync(through: three.mailbox)
        #expect(resent.entriesSent == 0, "an untouched packet was treated as altered and sent again")
    }
}
