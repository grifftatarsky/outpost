import Foundation
import Testing

@testable import CarpenterKit

@Suite("Entries")
struct EntryTests {
    private let identity = Identity.generate()
    private let device = DeviceKeys.generate()
    private let wallTime = Date(timeIntervalSince1970: 1_786_635_000)
    private let room = ConversationID.room(UUID())
    private let chain = EpochChain.create(room: ConversationID.room(UUID())).chain
    private var writer: FeedKey { FeedKey(author: identity.id, device: device.id, conversation: room) }

    private func seal(_ text: String) throws -> SealedPayload {
        try Payload.post(text).sealed(at: .initial, using: chain, by: writer)
    }

    private func append(to previous: Entry?, text: String = "hello") throws -> Entry {
        try Entry.append(
            to: previous,
            author: identity.id,
            device: device,
            clock: previous?.clock ?? VectorClock(),
            wallTime: wallTime,
            conversation: room,
            payload: try seal(text)
        )
    }

    @Test("The first entry in a feed is sequence one, and its clock records that")
    func firstEntry() throws {
        let entry = try append(to: nil)

        #expect(entry.seq == Entry.firstSequence)
        #expect(entry.previous == nil)
        #expect(entry.clock[entry.feedKey] == Entry.firstSequence)
    }

    @Test("Observing the first entry of a feed is visible in a clock")
    func firstEntryIsObservable() throws {
        let entry = try append(to: nil)
        var clock = VectorClock()
        clock.observe(entry.feedKey, seq: entry.seq)

        #expect(clock[entry.feedKey] == entry.seq)
        #expect(!clock.isEmpty)
    }

    @Test("Each append takes the next sequence number and links to its predecessor")
    func chaining() throws {
        let first = try append(to: nil)
        let second = try append(to: first)

        #expect(second.seq == 2)
        #expect(second.previous == first.hash)
        #expect(second.clock[second.feedKey] == 2)
    }

    @Test("An entry's signature verifies under the device that appended it")
    func signature() throws {
        let entry = try append(to: nil)

        #expect(try entry.hasValidSignature(from: device.publicKey))
        #expect(try !entry.hasValidSignature(from: DeviceKeys.generate().publicKey))
    }

    @Test("Every field is signed — changing any of them breaks the signature")
    func everyFieldIsCovered() throws {
        let entry = try append(to: nil)

        func mutated(_ transform: (Entry) -> Entry) throws -> Bool {
            try transform(entry).hasValidSignature(from: device.publicKey)
        }

        #expect(
            try !mutated {
                Entry(
                    author: $0.author, device: $0.device, seq: 99, previous: $0.previous,
                    clock: $0.clock, wallTime: $0.wallTime, conversation: $0.conversation, payload: $0.payload,
                    signature: $0.signature)
            })
        #expect(
            try !mutated {
                Entry(
                    author: $0.author, device: $0.device, seq: $0.seq, previous: $0.previous,
                    clock: $0.clock, wallTime: $0.wallTime.addingTimeInterval(1), conversation: $0.conversation,
                    payload: $0.payload, signature: $0.signature)
            })
        #expect(
            try !mutated {
                Entry(
                    author: $0.author, device: $0.device, seq: $0.seq, previous: $0.previous,
                    clock: $0.clock, wallTime: $0.wallTime, conversation: ConversationID.room(UUID()), payload: $0.payload,
                    signature: $0.signature)
            })
        #expect(
            try !mutated {
                Entry(
                    author: $0.author, device: $0.device, seq: $0.seq, previous: $0.previous,
                    clock: $0.clock, wallTime: $0.wallTime, conversation: $0.conversation,
                    payload: try! seal("tampered"), signature: $0.signature)
            })
    }

    @Test("An Outpost entry and a room entry with the same text are different entries")
    func roomIsPartOfIdentity() throws {
        let onWall = try Entry.append(
            to: nil, author: identity.id, device: device, clock: VectorClock(),
            wallTime: wallTime, conversation: .outpost(identity.id), payload: try seal("hello"))
        let inRoom = try append(to: nil)

        #expect(onWall.hash != inRoom.hash)
    }

    @Test("The hash covers the signature, so it identifies one exact entry")
    func hashCoversSignature() throws {
        let entry = try append(to: nil)
        let forged = Entry(
            author: entry.author, device: entry.device, seq: entry.seq, previous: entry.previous,
            clock: entry.clock, wallTime: entry.wallTime, conversation: entry.conversation, payload: entry.payload,
            signature: Data(repeating: 0, count: 64))

        #expect(forged.hash != entry.hash)
    }

    @Test("Hashing is stable across encoding, because entries travel between devices")
    func codableRoundTrip() throws {
        let entry = try append(to: nil)
        let restored = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(entry))

        #expect(restored == entry)
        #expect(restored.hash == entry.hash)
        #expect(try restored.hasValidSignature(from: device.publicKey))
    }

    @Test("A payload this client cannot read still hashes, signs and verifies")
    func unknownPayloadsAreStillEntries() throws {
        let unknown = Payload(
            type: PayloadType(rawValue: 9_999), version: 3, body: Data([0xDE, 0xAD]),
            fallbackText: "Nora posted a poll")

        let entry = try Entry.append(
            to: nil, author: identity.id, device: device, clock: VectorClock(),
            wallTime: wallTime, conversation: room,
            payload: try unknown.sealed(at: .initial, using: chain, by: writer))

        #expect(try entry.hasValidSignature(from: device.publicKey))
        #expect(entry.opened(using: chain)?.fallbackText == "Nora posted a poll")
    }

    @Test("A fallback string is part of what is signed")
    func fallbackIsSigned() throws {
        let entry = try Entry.append(
            to: nil, author: identity.id, device: device, clock: VectorClock(),
            wallTime: wallTime, conversation: room,
            payload: try Payload(type: .post, body: Data([1]), fallbackText: "honest")
                .sealed(at: .initial, using: chain, by: writer))

        let swapped = Entry(
            author: entry.author, device: entry.device, seq: entry.seq, previous: entry.previous,
            clock: entry.clock, wallTime: entry.wallTime, conversation: entry.conversation,
            payload: try Payload(type: .post, body: Data([1]), fallbackText: "misleading")
                .sealed(at: .initial, using: chain, by: writer),
            signature: entry.signature)

        #expect(try !swapped.hasValidSignature(from: device.publicKey))
    }

    @Test("An absent fallback is distinguishable from an empty one")
    func absentIsNotEmpty() {
        let absent = Payload(type: .post, body: Data([1]), fallbackText: nil)
        let empty = Payload(type: .post, body: Data([1]), fallbackText: "")

        #expect(absent.canonicalBytes != empty.canonicalBytes)
    }
}
