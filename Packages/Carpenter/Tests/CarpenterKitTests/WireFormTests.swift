import Foundation
import Testing

@testable import CarpenterKit

@Suite("Wire form")
struct WireFormTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func encoded(_ entry: Entry) throws -> Data {
        try JSONEncoder().encode(entry)
    }

    @Test("No part of the message survives into the encoded entry")
    func nothingLeaks() throws {
        var alice = Author()
        let entry = try alice.post("the mooring mast drawings are 1:200", at: start)

        let wire = try encoded(entry)

        for fragment in ["mooring", "mast", "drawings", "1:200"] {
            #expect(
                !wire.contains(Data(fragment.utf8)),
                "\(fragment) reached the wire in plaintext")
        }
    }

    @Test("The fallback string does not leak either")
    func fallbackIsSealed() throws {
        var alice = Author()
        let poll = Payload(
            type: PayloadType(rawValue: 4_242), version: 1, body: Data([9]),
            fallbackText: "Cassilda posted a poll about the Hindenburg")
        let entry = try alice.append(poll, at: start)

        let wire = try encoded(entry)

        #expect(!wire.contains(Data("Cassilda".utf8)))
        #expect(!wire.contains(Data("Hindenburg".utf8)))
    }

    @Test("The payload type is not in the clear, so a relay cannot tell a post from a reaction")
    func typeIsSealed() throws {
        var alice = Author()
        let post = try alice.post("a balloon that made a decision", at: start)
        let reaction = try alice.append(
            Payload.reaction(post.hash, emoji: "🎈"), at: start.addingTimeInterval(1))

        #expect(post.payload.epoch == reaction.payload.epoch)
        #expect(!(try encoded(reaction).contains(Data("🎈".utf8))))
    }

    @Test("What is in the clear is exactly the routing metadata, and no more")
    func metadataIsAsAdvertised() throws {
        var alice = Author()
        let room = ConversationID.room(UUID())
        _ = try alice.append(Payload.post("first"), at: start, room: room)
        let entry = try alice.append(
            Payload.post("hydrogen, obviously"), at: start.addingTimeInterval(1), room: room)

        let fields = try JSONSerialization.jsonObject(with: encoded(entry)) as? [String: Any]
        let keys = Set(fields?.keys ?? [:].keys)

        #expect(
            keys == [
                "author", "device", "seq", "previous", "clock", "wallTime", "room", "payload",
                "signature",
            ])

        let payload = fields?["payload"] as? [String: Any]
        #expect(Set(payload?.keys ?? [:].keys) == ["epoch", "ciphertext"])
    }

    @Test("An entry verifies and forwards without being readable")
    func verifiableWhileSealed() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        let entry = try alice.post("private", at: start)

        #expect(try replica.integrate(entry) == .accepted)
        #expect(try entry.hasValidSignature(from: alice.device.publicKey))

        let withoutKeys = EpochChain(room: ConversationID.room(UUID()))
        #expect(entry.opened(using: withoutKeys) == nil)
    }

    @Test("An entry this device cannot decrypt renders as sealed rather than vanishing")
    func unreadableEntriesAreVisible() throws {
        var alice = Author()
        let entry = try alice.post("private", at: start)

        let rendered = Fold.render([entry], using: EpochChain(room: ConversationID.room(UUID())))

        #expect(rendered.count == 1)
        #expect(rendered.first?.content == .sealed)
        #expect(rendered.first?.author == alice.identity.id)
    }

    @Test("Tampering with the ciphertext breaks the signature, not just the decryption")
    func ciphertextIsSigned() throws {
        var alice = Author()
        let entry = try alice.post("private", at: start)

        var bytes = entry.payload.ciphertext
        bytes[bytes.count / 2] ^= 0xFF
        let tampered = Entry(
            author: entry.author, device: entry.device, seq: entry.seq, previous: entry.previous,
            clock: entry.clock, wallTime: entry.wallTime, room: entry.room,
            payload: SealedPayload(epoch: entry.payload.epoch, ciphertext: bytes),
            signature: entry.signature)

        #expect(try !tampered.hasValidSignature(from: alice.device.publicKey))
        #expect(tampered.hash != entry.hash)
    }
}
