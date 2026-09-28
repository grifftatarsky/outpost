@testable import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("Each entry names its author's last entry in the room, and a removal counts only that chain")
struct TheRoomChainTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func seeing(_ key: FeedKey, seq: UInt64) -> VectorClock {
        var clock = VectorClock()
        clock.observe(key, seq: seq)
        return clock
    }

    private func room() throws -> (alice: Author, sam: Author, room: RoomID, entries: [Entry]) {
        let chain = EpochChain.create(room: RoomID())
        var alice = Author(chain: chain.chain)
        let sam = Author(chain: chain.chain)
        let room = chain.chain.room
        var entries: [Entry] = []
        entries.append(try alice.append(try Payload.roomProfile(name: "Hangar 7"), at: start, room: room))
        let invite = try TestInvite.issue(
            joining: room, joinerKeys: sam.identity.publicKeys, by: alice.identity, at: start)
        entries.append(
            try alice.append(try Payload.joinRequest(invite), at: start.addingTimeInterval(1), room: room))
        entries.append(
            try alice.append(
                try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: sam.identity)),
                at: start.addingTimeInterval(2), room: room))
        return (alice, sam, room, entries)
    }

    private func out(_ entries: [Entry], viewer: ParticipantID, chain: EpochChain, room: RoomID) -> Set<EntryHash> {
        let projected = Projection(
            viewer: viewer, rendered: LogRenderer.render(entries, using: chain), chains: RoomChains(entries))
        return projected.outOfRoom(in: room, opening: { rendered in
            entries.first { $0.hash == rendered.id }?.opened(using: chain)
        })
    }

    private func forged(
        by author: Author, after previous: Entry, inRoomAfter link: RoomLink?, room: RoomID, saying text: String
    ) throws -> Entry {
        try Entry.append(
            after: previous.link, author: author.identity.id, device: author.device, clock: previous.clock,
            wallTime: start, room: room, payload: try Payload.post(text), at: .initial, sealedWith: author.chain,
            roomLink: link)
    }

    // MARK: The bytes

    @Test("An entry from before rooms were chained signs exactly the bytes it always did")
    func theOldLayoutIsUnchanged() {
        let author = ParticipantID(rawValue: Data(repeating: 1, count: 32))
        let device = DeviceID(rawValue: Data(repeating: 2, count: 32))
        let room = RoomID()
        let payload = SealedPayload(epoch: .initial, ciphertext: Data([0xAB]))
        let entry = Entry(
            author: author, device: device, seq: 1, previous: nil, clock: VectorClock(), wallTime: start,
            room: room, payload: payload, signature: Data())
        let expected = CanonicalBytes.payload(
            domain: Domain.entry,
            fields: [
                author.rawValue, device.rawValue, CanonicalBytes.sequence(1), Data([0]),
                VectorClock().canonicalBytes, CanonicalBytes.timestamp(start), Data([1]), room.canonicalBytes,
                payload.canonicalBytes,
            ])
        #expect(
            entry.signingPayload == expected,
            "every signature taken over an entry written before the room chain stopped matching")
    }

    @Test("A chained entry signs its link last, and the first in a room signs an empty one")
    func theLinkIsSignedLast() {
        let author = ParticipantID(rawValue: Data(repeating: 1, count: 32))
        let device = DeviceID(rawValue: Data(repeating: 2, count: 32))
        let room = RoomID()
        let payload = SealedPayload(epoch: .initial, ciphertext: Data([0xAB]))
        let before = EntryHash(rawValue: Data(repeating: 9, count: 32))
        let base: [Data] = [
            author.rawValue, device.rawValue, CanonicalBytes.sequence(2), Data([0]), VectorClock().canonicalBytes,
            CanonicalBytes.timestamp(start), Data([1]), room.canonicalBytes, payload.canonicalBytes,
        ]
        for (link, bytes) in [(RoomLink(previous: before), before.rawValue), (RoomLink(previous: nil), Data())] {
            let entry = Entry(
                author: author, device: device, seq: 2, previous: nil, clock: VectorClock(), wallTime: start,
                room: room, payload: payload, signature: Data(), roomLink: link)
            #expect(
                entry.signingPayload
                    == CanonicalBytes.payload(domain: Domain.entry, fields: base + [Data("room-link".utf8), bytes]))
        }
    }

    @Test("A link is signed: changing it breaks the entry")
    func theLinkIsSigned() throws {
        var (_, sam, room, _) = try room()
        let first = try sam.append(try Payload.post("one"), at: start + 10, room: room, chained: true)
        let second = try sam.append(try Payload.post("two"), at: start + 11, room: room, chained: true)
        #expect(second.roomLink?.previous == first.hash)
        let moved = Entry(
            author: second.author, device: second.device, seq: second.seq, previous: second.previous,
            clock: second.clock, wallTime: second.wallTime, room: second.room, payload: second.payload,
            signature: second.signature, roomLink: RoomLink(previous: nil))
        #expect(moved.hash != second.hash)
        #expect(try !moved.hasValidSignature(from: sam.device.publicKey))
    }

    @Test("A chained entry reads back with its link, and an unchained one writes no link at all")
    func theStoredForm() throws {
        var (_, sam, room, _) = try room()
        let unchained = try sam.append(try Payload.post("old"), at: start + 10, room: room)
        let chained = try sam.append(try Payload.post("new"), at: start + 11, room: room, chained: true)

        let reread = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(chained))
        #expect(reread.hash == chained.hash)
        #expect(reread.roomLink == RoomLink(previous: unchained.hash))
        let keys = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(unchained)) as? [String: Any]).keys
        #expect(!keys.contains("roomLink"))
    }

    // MARK: What a removal counts

    @Test("An entry under a number the room never held, signed after the removal, does not count")
    func theGapIsClosed() throws {
        var (alice, sam, room, entries) = try room()
        let elsewhere = RoomID()
        let one = try sam.append(try Payload.post("one"), at: start + 10, room: room, chained: true)
        let two = try sam.append(try Payload.post("two"), at: start + 11, room: room, chained: true)
        _ = try sam.append(try Payload.post("in a room Alice is not in"), at: start + 12, room: elsewhere, chained: true)
        let four = try sam.append(try Payload.post("four"), at: start + 13, room: room, chained: true)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id, heads: [four.hash]), clock: seeing(sam.feedKey, seq: four.seq),
            at: start + 20, room: room)
        let slipped = try forged(
            by: sam, after: two, inRoomAfter: RoomLink(previous: two.hash), room: room,
            saying: "said before I was removed, honestly")
        let unchained = try forged(
            by: sam, after: two, inRoomAfter: nil, room: room, saying: "written the old way, under the same number")
        entries += [one, two, four, removal, slipped, unchained]

        #expect(slipped.seq == 3, "precondition: the forgery takes the number used in the other room")
        let gone = out(entries, viewer: alice.identity.id, chain: alice.chain, room: room)
        #expect(gone.contains(slipped.hash), "an entry signed after the removal counted under a number the room never held")
        #expect(gone.contains(unchained.hash), "leaving the link off let a forgery count")
        #expect(gone.isDisjoint(with: [one.hash, two.hash, four.hash]), "the removal dropped words on its own chain")
    }

    @Test("Words the remover never received still count when they are on the chain")
    func anHonestRemoverDropsNothingOnTheChain() throws {
        var (alice, sam, room, entries) = try room()
        let one = try sam.append(try Payload.post("one"), at: start + 10, room: room, chained: true)
        let missed = try sam.append(try Payload.post("never reached Alice"), at: start + 11, room: room, chained: true)
        let three = try sam.append(try Payload.post("three"), at: start + 12, room: room, chained: true)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id, heads: [three.hash]), clock: seeing(sam.feedKey, seq: three.seq),
            at: start + 20, room: room)
        entries += [one, three, removal, missed]

        let carol = Identity.generate().id
        #expect(
            !out(entries, viewer: carol, chain: alice.chain, room: room).contains(missed.hash),
            "a message on the chain was dropped because the remover had not received it")
    }

    @Test("A reaction in the middle of the chain does not break it")
    func aReactionIsPartOfTheChain() throws {
        var (alice, sam, room, entries) = try room()
        let one = try sam.append(try Payload.post("one"), at: start + 10, room: room, chained: true)
        let reacting = try sam.append(try Payload.reaction(one.hash, emoji: "👍"), at: start + 11, room: room, chained: true)
        let three = try sam.append(try Payload.post("three"), at: start + 12, room: room, chained: true)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id, heads: [three.hash]), clock: seeing(sam.feedKey, seq: three.seq),
            at: start + 20, room: room)
        entries += [one, reacting, three, removal]

        #expect(!out(entries, viewer: alice.identity.id, chain: alice.chain, room: room).contains(one.hash))
    }

    @Test("Words from before rooms were chained count up to where the chain begins, and no further")
    func theUnchainedPastIsBounded() throws {
        var (alice, sam, room, entries) = try room()
        let old = try sam.append(try Payload.post("written before chains"), at: start + 10, room: room)
        let elsewhere = try sam.append(try Payload.post("another room"), at: start + 11, room: RoomID())
        let chained = try sam.append(try Payload.post("the first chained"), at: start + 12, room: room, chained: true)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id, heads: [chained.hash]),
            clock: seeing(sam.feedKey, seq: chained.seq), at: start + 20, room: room)
        let slipped = try forged(
            by: sam, after: old, inRoomAfter: nil, room: room, saying: "an old-style entry past where the chain begins")
        entries += [old, chained, removal, slipped]

        #expect(chained.roomLink?.previous == old.hash, "precondition: the chain begins at the old entry")
        #expect(slipped.seq == elsewhere.seq, "precondition: the forgery takes the other room's number")
        let gone = out(entries, viewer: alice.identity.id, chain: alice.chain, room: room)
        #expect(!gone.contains(old.hash), "an entry from before chains was dropped")
        #expect(!gone.contains(chained.hash))
        #expect(gone.contains(slipped.hash), "an unchained entry past the start of the chain counted")
    }

    @Test("A removal written before heads existed still goes by what its clock saw")
    func anOlderRemovalGoesByItsClock() throws {
        var (alice, sam, room, entries) = try room()
        let seen = try sam.append(try Payload.post("seen"), at: start + 10, room: room, chained: true)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id), clock: seeing(sam.feedKey, seq: seen.seq), at: start + 20,
            room: room)
        let later = try sam.append(try Payload.post("after"), at: start + 21, room: room, chained: true)
        entries += [seen, removal, later]

        let gone = out(entries, viewer: alice.identity.id, chain: alice.chain, room: room)
        #expect(!gone.contains(seen.hash))
        #expect(gone.contains(later.hash))
    }

    @Test("Somebody who leaves names their own chain, and nothing slipped in under another number counts")
    func leavingNamesTheChain() throws {
        var (alice, sam, room, entries) = try room()
        let one = try sam.append(try Payload.post("one"), at: start + 10, room: room, chained: true)
        _ = try sam.append(try Payload.post("elsewhere"), at: start + 11, room: RoomID(), chained: true)
        let three = try sam.append(try Payload.post("three"), at: start + 12, room: room, chained: true)
        let leaving = try sam.append(
            try Payload.departure(heads: [three.hash]), at: start + 13, room: room, chained: true)
        let slipped = try forged(
            by: sam, after: one, inRoomAfter: RoomLink(previous: one.hash), room: room, saying: "slipped in")
        entries += [one, three, leaving, slipped]

        let gone = out(entries, viewer: alice.identity.id, chain: alice.chain, room: room)
        #expect(gone.contains(slipped.hash), "an entry under another room's number counted after they left")
        #expect(gone.isDisjoint(with: [one.hash, three.hash]))
    }
}

@MainActor
@Suite("The app links each entry it writes to its last one in the room, across a relaunch", .serialized)
struct TheAppWritesTheRoomChainTests {
    @Test("Each entry names this device's last one in the room, and the first names none")
    func eachEntryNamesTheLastOne() async throws {
        let keychain = InMemoryKeychainStore()
        let directory = TestScratch.root.appending(path: "carpenter-chain-\(UUID().uuidString)")
        let alice = TestSession.make(keychain: keychain, at: directory)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let room = try await alice.createRoom(named: "Chained")
        let other = try await alice.createRoom(named: "Elsewhere")
        try await alice.send("one", to: room)
        try await alice.send("somewhere else", to: other)
        try await alice.send("two", to: room)

        let relaunched = TestSession.make(keychain: keychain, at: directory)
        await relaunched.load()
        try await relaunched.send("three", to: room)

        let me = try #require(relaunched.enrolment?.identity.id)
        let mine = relaunched.replica.allEntries.filter { $0.author == me && $0.room == room }.sorted { $0.seq < $1.seq }
        try #require(mine.count >= 4, "precondition: the room holds what was written")
        #expect(mine.first?.roomLink == RoomLink(previous: nil), "the first entry in the room named a previous one")
        for (earlier, later) in zip(mine, mine.dropFirst()) {
            #expect(later.roomLink?.previous == earlier.hash, "an entry skipped or broke the chain in its room")
        }
    }

    @Test("A removal names the last entry of each of the removed person's devices that the remover holds")
    func aRemovalNamesItsHeads() async throws {
        let mailbox = InMemoryMailbox()
        let (alice, sam) = (TestSession.make(), TestSession.make())
        for (session, name) in [(alice, "Alice"), (sam, "Sam")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        let room = try await alice.createRoom(named: "Hangar")
        try await join(sam, into: room, of: alice, through: mailbox)
        try await sam.send("before", to: room)
        for _ in 0..<3 {
            try await sam.sync(through: mailbox)
            try await alice.sync(through: mailbox)
        }
        let samID = try #require(sam.enrolment?.identity.id)
        let last = try #require(
            alice.replica.allEntries.filter { $0.author == samID && $0.room == room }.max { $0.seq < $1.seq })

        try await alice.remove(samID, from: room)

        let removal = try #require(
            alice.replica.allEntries.last { entry in
                entry.room == room && alice.chain(sealing: entry).flatMap(entry.opened(using:))?.type == .removal
            })
        let body = try #require(try alice.chain(sealing: removal).flatMap(removal.opened(using:))?.decode(RemovalBody.self))
        #expect(body.heads == [last.hash], "the removal did not name the last entry it held")
        #expect(
            alice.messages(in: room).contains { $0.body == "before" },
            "a message on the removed person's chain was dropped")
    }
}
