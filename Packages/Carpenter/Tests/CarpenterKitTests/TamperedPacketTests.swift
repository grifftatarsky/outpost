@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Nobody who can write to your outbox can make a message miss the others", .serialized)
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

    private func lastPacket(from three: Three, after before: Set<PacketID>) async throws -> PacketID {
        let written = await three.mailbox.writtenPackets.filter { !before.contains($0) }
        return try #require(written.last, "precondition: Alice wrote a packet")
    }

    @Test("A partner who strips the others from a packet does not make its sender take it back")
    func strippedRecipientsDoNotSettle() async throws {
        let three = try await three()
        let before = Set(await three.mailbox.writtenPackets)
        try await three.alice.send("for both of you", to: three.room)
        try await three.alice.sync(through: three.mailbox)
        let packet = try await lastPacket(from: three, after: before)

        let bobsTags = Set(try await three.mailbox.sentPackets()[packet].map(\.recipients) ?? [])
        let beforeBob = Set(await three.mailbox.writtenPackets)
        try await three.bob.sync(through: three.mailbox)
        for relayed in await three.mailbox.writtenPackets where !beforeBob.contains(relayed) {
            await three.mailbox.delete(packet: relayed)
        }
        #expect(three.bob.messages(in: three.room).contains { $0.body == "for both of you" })
        let signedFor = try #require(try await three.mailbox.sentPackets()[packet])
        let bobs = Set(signedFor.receipts.map(\.tag))
        try #require(!bobs.isEmpty, "precondition: Bob signed for it")
        await three.mailbox.tamper(packet: packet) { fields in
            guard case .dataList(let tags)? = fields[PacketWire.wrapTags],
                case .dataList(let values)? = fields[PacketWire.wrapValues]
            else { return }
            let kept = zip(tags, values).filter { bobs.contains(RecipientTag(rawValue: $0.0)) }
            fields[PacketWire.wrapTags] = .dataList(kept.map(\.0))
            fields[PacketWire.wrapValues] = .dataList(kept.map(\.1))
            fields[PacketWire.outstanding] = .dataList(kept.map(\.0))
        }
        try #require(bobsTags.count > 1, "precondition: the packet was for more than Bob")

        try await three.alice.sync(through: three.mailbox)
        try await three.carol.sync(through: three.mailbox)
        try await three.alice.sync(through: three.mailbox)
        try await three.carol.sync(through: three.mailbox)
        #expect(
            three.carol.messages(in: three.room).contains { $0.body == "for both of you" },
            "Bob made Alice take back a message Carol never collected")
    }

    @Test("A packet changed on the server after it was written is sent again")
    func alteredPacketIsSentAgain() async throws {
        let three = try await three()
        let before = Set(await three.mailbox.writtenPackets)
        try await three.alice.send("untouched", to: three.room)
        try await three.alice.sync(through: three.mailbox)
        let packet = try await lastPacket(from: three, after: before)

        await three.mailbox.tamper(packet: packet) { fields in
            guard case .data(var sealed)? = fields[PacketWire.ciphertext], !sealed.isEmpty else { return }
            sealed[sealed.startIndex] ^= 0xFF
            fields[PacketWire.ciphertext] = .data(sealed)
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
