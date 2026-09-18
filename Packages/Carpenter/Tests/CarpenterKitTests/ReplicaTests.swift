import Foundation
import Testing

@testable import CarpenterKit

struct Author {
    let identity: Identity
    let device: DeviceKeys
    let certificate: DeviceCertificate
    let chain: EpochChain
    private(set) var head: Entry?

    init(at issuedAt: Date = Date(timeIntervalSince1970: 0), chain: EpochChain? = nil) {
        identity = Identity.generate()
        device = DeviceKeys.generate()
        certificate = try! DeviceCertificate.issue(
            for: device.publicKey, by: identity, at: issuedAt)
        self.chain = chain ?? EpochChain.create(room: RoomID()).chain
    }

    var feedKey: FeedKey { FeedKey(author: identity.id, device: device.id) }

    mutating func append(
        _ payload: Payload, clock: VectorClock = VectorClock(), at wallTime: Date,
        room: RoomID? = nil
    ) throws -> Entry {
        let entry = try Entry.append(
            to: head, author: identity.id, device: device,
            clock: clock.merging(head?.clock ?? VectorClock()),
            wallTime: wallTime, room: room, payload: payload, at: .initial, sealedWith: chain)
        head = entry
        return entry
    }

    mutating func post(_ text: String, clock: VectorClock = VectorClock(), at wallTime: Date)
        throws -> Entry
    {
        try append(Payload.post(text), clock: clock, at: wallTime)
    }
}

extension Replica {
    mutating func meet(_ author: Author) throws {
        introduce(author.identity.publicKeys)
        try admit(author.certificate)
    }
}

@Suite("Replica")
struct ReplicaTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func seal(_ text: String, as author: Author) throws -> SealedPayload {
        try Payload.post(text).sealed(at: .initial, using: author.chain)
    }

    @Test("An entry from a known member on a certified device is accepted")
    func acceptsValidEntry() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        let entry = try alice.post("hello", at: start)

        #expect(try replica.integrate(entry) == .accepted)
        #expect(replica.entryCount == 1)
    }

    @Test("Nothing is accepted from a member the replica has never been introduced to")
    func refusesUnknownParticipant() throws {
        var stranger = Author()
        var replica = Replica()

        let entry = try stranger.post("hello", at: start)

        #expect(throws: LogError.unknownParticipant) { try replica.integrate(entry) }
    }

    @Test("An entry from an uncertified device of a known member is refused")
    func refusesUncertifiedDevice() throws {
        let alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        let rogue = DeviceKeys.generate()
        let entry = try Entry.append(
            to: nil, author: alice.identity.id, device: rogue, clock: VectorClock(),
            wallTime: start, room: nil, payload: try seal("not me", as: alice))

        #expect(throws: LogError.unauthorizedDevice) { try replica.integrate(entry) }
    }

    @Test("An entry whose signature does not match is refused")
    func refusesBadSignature() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        let genuine = try alice.post("hello", at: start)
        let tampered = Entry(
            author: genuine.author, device: genuine.device, seq: genuine.seq,
            previous: genuine.previous, clock: genuine.clock, wallTime: genuine.wallTime,
            room: genuine.room, payload: try seal("not what she said", as: alice),
            signature: genuine.signature)

        #expect(throws: LogError.badSignature) { try replica.integrate(tampered) }
    }

    @Test("Integrating the same entry twice changes nothing")
    func idempotent() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        let entry = try alice.post("hello", at: start)
        try replica.integrate(entry)

        #expect(try replica.integrate(entry) == .alreadyPresent)
        #expect(replica.entryCount == 1)
    }

    @Test("An entry claiming a predecessor this replica does not hold is not refused — that is a gap, not a lie")
    func toleratesGaps() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        _ = try alice.post("first", at: start)
        let second = try alice.post("second", at: start.addingTimeInterval(1))

        #expect(try replica.integrate(second) == .accepted)
    }

    @Test("An entry that names the wrong predecessor is refused")
    func refusesBrokenLink() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        let first = try alice.post("first", at: start)
        try replica.integrate(first)

        let forged = try Entry.append(
            to: nil, author: alice.identity.id, device: alice.device, clock: VectorClock(),
            wallTime: start, room: nil, payload: try seal("second", as: alice))
        let relabelled = Entry(
            author: forged.author, device: forged.device, seq: 2,
            previous: EntryHash(rawValue: Data(repeating: 0, count: 32)), clock: forged.clock,
            wallTime: forged.wallTime, room: forged.room, payload: forged.payload,
            signature: forged.signature)

        #expect(throws: LogError.self) { try replica.integrate(relabelled) }
    }

    @Test("A first entry that claims a predecessor is refused")
    func refusesRootWithPredecessor() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        let genuine = try alice.post("first", at: start)
        let forged = Entry(
            author: genuine.author, device: genuine.device, seq: Entry.firstSequence,
            previous: EntryHash(rawValue: Data(repeating: 1, count: 32)), clock: genuine.clock,
            wallTime: genuine.wallTime, room: genuine.room, payload: genuine.payload,
            signature: genuine.signature)

        #expect(throws: LogError.self) { try replica.integrate(forged) }
    }

    @Test("Two entries at the same position in one feed are reported as a fork, and both are kept")
    func detectsForks() throws {
        let alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        let left = try Entry.append(
            to: nil, author: alice.identity.id, device: alice.device, clock: VectorClock(),
            wallTime: start, room: nil, payload: try seal("one story", as: alice))
        let right = try Entry.append(
            to: nil, author: alice.identity.id, device: alice.device, clock: VectorClock(),
            wallTime: start, room: nil, payload: try seal("another story", as: alice))

        try replica.integrate(left)
        let result = try replica.integrate(right)

        guard case .forked(let fork) = result else {
            Issue.record("expected a fork, got \(result)")
            return
        }
        #expect(fork.feed == alice.feedKey)
        #expect(fork.seq == Entry.firstSequence)
        #expect(fork.hashes == [left.hash, right.hash])
        #expect(replica.entryCount == 2)
        #expect(replica.hasDiverged)
    }

    @Test("A fork is reported once, not once per re-delivery")
    func forksAreNotDuplicated() throws {
        let alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        let left = try Entry.append(
            to: nil, author: alice.identity.id, device: alice.device, clock: VectorClock(),
            wallTime: start, room: nil, payload: try seal("one", as: alice))
        let right = try Entry.append(
            to: nil, author: alice.identity.id, device: alice.device, clock: VectorClock(),
            wallTime: start, room: nil, payload: try seal("two", as: alice))

        try replica.integrate(left)
        try replica.integrate(right)
        try replica.integrate(right)

        #expect(replica.forks.count == 1)
    }

    @Test("A revoked device's later entries are refused, and its earlier ones stand")
    func honoursRevocation() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        let before = try alice.post("before", at: start)
        try replica.integrate(before)

        let revokedAt = start.addingTimeInterval(3_600)
        try replica.revoke(
            DeviceRevocation.issue(for: alice.device.id, by: alice.identity, at: revokedAt))

        let after = try alice.post("after", at: revokedAt.addingTimeInterval(60))

        #expect(throws: LogError.unauthorizedDevice) { try replica.integrate(after) }
        #expect(replica.entryCount == 1)
    }

    @Test("Entries are filtered by room, and an Outpost is just the feed with no room")
    func filtersByRoom() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        let room = RoomID()
        try replica.integrate(try alice.append(Payload.post("on my Outpost"), at: start, room: nil))
        try replica.integrate(
            try alice.append(
                Payload.post("in the room"), at: start.addingTimeInterval(1), room: room))

        #expect(replica.entries(in: nil).count == 1)
        #expect(replica.entries(in: room).count == 1)
    }

    @Test("The frontier reports how far each feed has been seen, ready for the next append")
    func frontier() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        try replica.integrate(try alice.post("one", at: start))
        try replica.integrate(try alice.post("two", at: start.addingTimeInterval(1)))

        #expect(replica.frontier[alice.feedKey] == 2)
    }

    @Test("An entry of a type this client cannot read is stored and kept, not dropped")
    func keepsUnknownPayloads() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        let future = Payload(
            type: PayloadType(rawValue: 4_242), version: 7, body: Data([1, 2, 3]),
            fallbackText: "Cassilda posted a poll")
        let entry = try alice.append(future, at: start)

        #expect(try replica.integrate(entry) == .accepted)
        #expect(
            replica.allEntries.first?.opened(using: alice.chain)?.body == Data([1, 2, 3]))
    }
}
