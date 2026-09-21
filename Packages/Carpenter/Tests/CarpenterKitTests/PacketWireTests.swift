import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Packet wire mapping")
struct PacketWireTests {
    private func peers() throws -> (mine: Peer, theirs: Peer) {
        let a = Identity.generate()
        let b = Identity.generate()
        return (
            Peer(
                secret: try PairwiseSecret.derive(mine: a, theirs: b.publicKeys),
                them: b.id, me: a.id),
            Peer(
                secret: try PairwiseSecret.derive(mine: b, theirs: a.publicKeys),
                them: a.id, me: b.id)
        )
    }

    @Test("Every part of a packet survives the round trip")
    func roundTripIsComplete() throws {
        let (mine, _) = try peers()
        var author = Author()

        let room = ConversationID.room(UUID())
        let (_, secret) = EpochChain.create(room: room)
        let grant = try EpochGrant.issue(secret, at: .initial, in: room, link: nil, to: mine.secret)

        let packet = try SyncEngine.pack(
            [try author.post("evening", at: TestSession.now)],
            for: [mine], granting: [(to: mine, grant: grant)], window: 7)

        let restored = try #require(PacketWire.packet(from: PacketWire.fields(of: packet)))

        #expect(restored == packet, "the wire mapping lost part of the packet")
    }

    @Test("A packet with no grants round-trips as a packet with no grants")
    func emptyGrantsAreNotAFailure() throws {
        let (mine, _) = try peers()
        var author = Author()

        let packet = try SyncEngine.pack(
            [try author.post("nothing to hand over", at: TestSession.now)], for: [mine], window: 7)
        #expect(packet.grants.isEmpty, "precondition")

        let restored = try #require(PacketWire.packet(from: PacketWire.fields(of: packet)))
        #expect(restored == packet)
    }

    @Test("Fields written before grants existed still read")
    func forwardsFromAnOlderWriter() throws {
        let (mine, _) = try peers()
        var author = Author()

        let packet = try SyncEngine.pack(
            [try author.post("from an older build", at: TestSession.now)], for: [mine], window: 7)

        var fields = PacketWire.fields(of: packet)
        fields[PacketWire.grantTags] = nil
        fields[PacketWire.grantValues] = nil

        let restored = try #require(PacketWire.packet(from: fields))
        #expect(restored.ciphertext == packet.ciphertext)
        #expect(restored.wraps == packet.wraps)
        #expect(restored.grants.isEmpty)
    }

    @Test("A half-written grant reads as no grant, not as a wrong one")
    func mismatchedGrantArraysAreDropped() throws {
        let (mine, _) = try peers()
        let room = ConversationID.room(UUID())
        let (_, secret) = EpochChain.create(room: room)
        let grant = try EpochGrant.issue(secret, at: .initial, in: room, link: nil, to: mine.secret)

        let packet = try SyncEngine.pack(
            [], for: [mine], granting: [(to: mine, grant: grant)], window: 7)

        var fields = PacketWire.fields(of: packet)
        fields[PacketWire.grantValues] = .dataList([])

        let restored = try #require(PacketWire.packet(from: fields))
        #expect(restored.grants.isEmpty)
    }

    @Test("Fields that cannot make a packet make no packet")
    func undecodableIsNil() {
        #expect(PacketWire.packet(from: [:]) == nil)
        #expect(PacketWire.packet(from: [PacketWire.packetID: .string("not-a-uuid")]) == nil)
    }

    @Test("The in-memory mailbox carries a grant through the wire mapping")
    func fakeMailboxSerialises() async throws {
        let (mine, theirs) = try peers()
        let room = ConversationID.room(UUID())
        let (_, secret) = EpochChain.create(room: room)
        let grant = try EpochGrant.issue(secret, at: .initial, in: room, link: nil, to: mine.secret)

        let mailbox = InMemoryMailbox()
        let packet = try SyncEngine.pack(
            [], for: [mine], granting: [(to: mine, grant: grant)], window: 7)
        try await mailbox.put(packet)

        let collected = try await mailbox.fetch(for: theirs.incomingTag(window: 7))
        #expect(collected.count == 1)
        #expect(collected.first?.grants == packet.grants, "the fake mailbox skipped serialisation")
    }
}
