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
        entries += try admit(sam.identity, by: &alice, into: room, at: start + 1)
        return (alice, sam, room, entries)
    }

    private func admit(
        _ joiner: Identity, by inviter: inout Author, into room: RoomID, at time: Date
    ) throws -> [Entry] {
        let invite = try TestInvite.issue(joining: room, joinerKeys: joiner.publicKeys, by: inviter.identity, at: start)
        return [
            try inviter.append(try Payload.joinRequest(invite), at: time, room: room),
            try inviter.append(
                try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: joiner)),
                at: time + 1, room: room),
        ]
    }

    private func standing(_ entries: [Entry], chain: EpochChain, room: RoomID) -> Projection.Standing {
        Projection(
            viewer: Identity.generate().id, rendered: LogRenderer.render(entries, using: chain),
            chains: RoomChains(entries)
        ).standing(in: room, opening: { rendered in entries.first { $0.hash == rendered.id }?.opened(using: chain) })
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
        let first = try sam.append(try Payload.post("one"), at: start + 10, room: room)
        let second = try sam.append(try Payload.post("two"), at: start + 11, room: room)
        #expect(second.roomLink?.previous == first.hash)
        let moved = Entry(
            author: second.author, device: second.device, seq: second.seq, previous: second.previous,
            clock: second.clock, wallTime: second.wallTime, room: second.room, payload: second.payload,
            signature: second.signature, roomLink: RoomLink(previous: nil))
        #expect(moved.hash != second.hash)
        #expect(try !moved.hasValidSignature(from: sam.device.publicKey))
    }

    @Test("A chained entry reads back with its link, and an entry outside a room writes no link at all")
    func theStoredForm() throws {
        var (_, sam, room, _) = try room()
        let first = try sam.append(try Payload.post("first"), at: start + 10, room: room)
        let chained = try sam.append(try Payload.post("second"), at: start + 11, room: room)
        let outside = try sam.append(try Payload.post("in no room"), at: start + 12)

        let reread = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(chained))
        #expect(reread.hash == chained.hash)
        #expect(reread.roomLink == RoomLink(previous: first.hash))
        let keys = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(outside)) as? [String: Any]).keys
        #expect(!keys.contains("roomLink"))
    }

    @Test("An entry in a room without a link is refused")
    func anUnlinkedEntryIsRefused() throws {
        var (_, sam, room, _) = try room()
        var replica = Replica()
        try replica.meet(sam)
        let unlinked = try Entry.append(
            to: nil, author: sam.identity.id, device: sam.device, clock: VectorClock(), wallTime: start,
            room: room, payload: try Payload.post("no link"), at: .initial, sealedWith: sam.chain)

        #expect(throws: LogError.brokenLink) { try replica.integrate(unlinked) }
        #expect(try replica.integrate(try sam.append(try Payload.post("linked"), at: start, room: room)) == .accepted)
    }

    // MARK: What a removal counts

    @Test("An entry under a number the room never held, signed after the removal, does not count")
    func theGapIsClosed() throws {
        var (alice, sam, room, entries) = try room()
        let elsewhere = RoomID()
        let one = try sam.append(try Payload.post("one"), at: start + 10, room: room)
        let two = try sam.append(try Payload.post("two"), at: start + 11, room: room)
        _ = try sam.append(try Payload.post("in a room Alice is not in"), at: start + 12, room: elsewhere)
        let four = try sam.append(try Payload.post("four"), at: start + 13, room: room)
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
        let gone = standing(entries, chain: alice.chain, room: room).out
        #expect(gone.contains(slipped.hash), "an entry signed after the removal counted under a number the room never held")
        #expect(gone.contains(unchained.hash), "leaving the link off let a forgery count")
        #expect(gone.isDisjoint(with: [one.hash, two.hash, four.hash]), "the removal dropped words on its own chain")
    }

    @Test("Words the remover never received still count when they are on the chain")
    func anHonestRemoverDropsNothingOnTheChain() throws {
        var (alice, sam, room, entries) = try room()
        let one = try sam.append(try Payload.post("one"), at: start + 10, room: room)
        let missed = try sam.append(try Payload.post("never reached Alice"), at: start + 11, room: room)
        let three = try sam.append(try Payload.post("three"), at: start + 12, room: room)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id, heads: [three.hash]), clock: seeing(sam.feedKey, seq: three.seq),
            at: start + 20, room: room)
        entries += [one, three, removal, missed]

        #expect(
            !standing(entries, chain: alice.chain, room: room).out.contains(missed.hash),
            "a message on the chain was dropped because the remover had not received it")
    }

    @Test("A reaction in the middle of the chain does not break it")
    func aReactionIsPartOfTheChain() throws {
        var (alice, sam, room, entries) = try room()
        let one = try sam.append(try Payload.post("one"), at: start + 10, room: room)
        let reacting = try sam.append(try Payload.reaction(one.hash, emoji: "👍"), at: start + 11, room: room)
        let three = try sam.append(try Payload.post("three"), at: start + 12, room: room)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id, heads: [three.hash]), clock: seeing(sam.feedKey, seq: three.seq),
            at: start + 20, room: room)
        entries += [one, reacting, three, removal]

        #expect(!standing(entries, chain: alice.chain, room: room).out.contains(one.hash))
    }

    @Test("Somebody who leaves names their own chain, and nothing slipped in under another number counts")
    func leavingNamesTheChain() throws {
        var (alice, sam, room, entries) = try room()
        let one = try sam.append(try Payload.post("one"), at: start + 10, room: room)
        _ = try sam.append(try Payload.post("elsewhere"), at: start + 11, room: RoomID())
        let three = try sam.append(try Payload.post("three"), at: start + 12, room: room)
        let leaving = try sam.append(try Payload.departure(heads: [three.hash]), at: start + 13, room: room)
        let slipped = try forged(
            by: sam, after: one, inRoomAfter: RoomLink(previous: one.hash), room: room, saying: "slipped in")
        entries += [one, three, leaving, slipped]

        let gone = standing(entries, chain: alice.chain, room: room).out
        #expect(gone.contains(slipped.hash), "an entry under another room's number counted after they left")
        #expect(gone.isDisjoint(with: [one.hash, three.hash]))
    }

    // MARK: Who is in the room

    @Test("Somebody removed cannot stay by removing the one who removed them: both are out")
    func aRemovalCannotBeAnsweredFromOutside() throws {
        var (alice, sam, room, entries) = try room()
        let said = try sam.append(try Payload.post("before"), at: start + 10, room: room)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id, heads: [said.hash]), clock: seeing(sam.feedKey, seq: said.seq),
            at: start + 20, room: room)
        let answer = try sam.append(
            try Payload.removal(of: alice.identity.id, heads: [entries[2].hash]), at: start + 19, room: room)
        entries += [said, removal, answer]

        let members = standing(entries, chain: alice.chain, room: room).roster.members
        #expect(
            !members.contains(sam.identity.id),
            """
            After Alice removed Sam, Sam wrote a removal of Alice dated a second before hers and claiming \
            not to have seen it. It was read first, so Alice's removal no longer counted and Sam stayed in.
            """)
        #expect(
            !members.contains(alice.identity.id),
            "two removals that each claim not to have seen the other have to leave both people out")
    }

    @Test("Somebody removed cannot remove anybody else, whatever date they write on it")
    func aRemovedPersonCannotRemoveAThird() throws {
        var (alice, sam, room, entries) = try room()
        let bob = Author(chain: alice.chain)
        entries += try admit(bob.identity, by: &alice, into: room, at: start + 5)
        let said = try sam.append(try Payload.post("before"), at: start + 10, room: room)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id, heads: [said.hash]), clock: seeing(sam.feedKey, seq: said.seq),
            at: start + 20, room: room)
        let answer = try sam.append(try Payload.removal(of: bob.identity.id, heads: []), at: start + 19, room: room)
        entries += [said, removal, answer]

        let members = standing(entries, chain: alice.chain, room: room).roster.members
        #expect(members.contains(bob.identity.id), "a removed person's backdated removal put somebody else out")
        #expect(members.contains(alice.identity.id))
        #expect(!members.contains(sam.identity.id))
    }

    @Test("Somebody removed cannot bring in a second identity by dating the invitation earlier")
    func aRemovedPersonCannotInviteFromOutside() throws {
        var (alice, sam, room, entries) = try room()
        let puppet = Identity.generate()
        let said = try sam.append(try Payload.post("before"), at: start + 10, room: room)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id, heads: [said.hash]), clock: seeing(sam.feedKey, seq: said.seq),
            at: start + 20, room: room)
        let invite = try TestInvite.issue(
            joining: room, joinerKeys: puppet.publicKeys, by: sam.identity, at: start)
        let asked = try sam.append(try Payload.joinRequest(invite), at: start + 18, room: room)
        let confirmed = try sam.append(
            try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: puppet)),
            at: start + 19, room: room)
        entries += [said, removal, asked, confirmed]

        let members = standing(entries, chain: alice.chain, room: room).roster.members
        #expect(
            !members.contains(puppet.id),
            """
            After Alice removed Sam, Sam wrote an invitation of a second identity and its confirmation, \
            dated before the removal. Both counted as written while Sam was in, so the second identity \
            stayed in the room.
            """)
        #expect(members.contains(alice.identity.id))
    }

    @Test("A second identity brought in from outside cannot remove the one who removed its maker")
    func aSecondIdentityCannotAnswerForItsMaker() throws {
        var (alice, sam, room, entries) = try room()
        var puppet = Author(chain: alice.chain)
        let said = try sam.append(try Payload.post("before"), at: start + 10, room: room)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id, heads: [said.hash]), clock: seeing(sam.feedKey, seq: said.seq),
            at: start + 20, room: room)
        let invite = try TestInvite.issue(
            joining: room, joinerKeys: puppet.identity.publicKeys, by: sam.identity, at: start)
        let asked = try sam.append(try Payload.joinRequest(invite), at: start + 17, room: room)
        let confirmed = try sam.append(
            try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: puppet.identity)),
            at: start + 18, room: room)
        let answer = try puppet.append(
            try Payload.removal(of: alice.identity.id, heads: [entries[2].hash]), at: start + 19, room: room)
        entries += [said, removal, asked, confirmed, answer]

        let members = standing(entries, chain: alice.chain, room: room).roster.members
        #expect(members.contains(alice.identity.id), "a second identity let in from outside removed the remover")
        #expect(!members.contains(sam.identity.id))
        #expect(!members.contains(puppet.identity.id))
    }

    @Test("Removed by two people, somebody cannot answer either of them")
    func twoRemovalsLeaveNothingToAnswer() throws {
        var (alice, sam, room, entries) = try room()
        var bob = Author(chain: alice.chain)
        entries += try admit(bob.identity, by: &alice, into: room, at: start + 5)
        let said = try sam.append(try Payload.post("before"), at: start + 10, room: room)
        let byAlice = try alice.append(
            try Payload.removal(of: sam.identity.id, heads: [said.hash]), clock: seeing(sam.feedKey, seq: said.seq),
            at: start + 20, room: room)
        let byBob = try bob.append(
            try Payload.removal(of: sam.identity.id, heads: [said.hash]), clock: seeing(sam.feedKey, seq: said.seq),
            at: start + 21, room: room)
        let answer = try sam.append(
            try Payload.removal(of: alice.identity.id, heads: [try #require(entries.last).hash]), at: start + 19,
            room: room)
        entries += [said, byAlice, byBob, answer]

        let members = standing(entries, chain: alice.chain, room: room).roster.members
        #expect(members.contains(alice.identity.id), "removed by two people, Sam still took one of them out")
        #expect(members.contains(bob.identity.id))
        #expect(!members.contains(sam.identity.id))
    }

    @Test("Answering a removal never lets back in somebody the remover had put out")
    func anAnswerTakesAwayAndNeverGives() throws {
        var (alice, sam, room, entries) = try room()
        let mallory = Author(chain: alice.chain)
        entries += try admit(mallory.identity, by: &alice, into: room, at: start + 5)
        let before = try #require(entries.last)
        let said = try sam.append(try Payload.post("before"), at: start + 10, room: room)
        let out = try alice.append(try Payload.removal(of: mallory.identity.id, heads: []), at: start + 12, room: room)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id, heads: [said.hash]), clock: seeing(sam.feedKey, seq: said.seq),
            at: start + 20, room: room)
        let answer = try sam.append(
            try Payload.removal(of: alice.identity.id, heads: [before.hash]), at: start + 19, room: room)
        entries += [said, out, removal, answer]

        let members = standing(entries, chain: alice.chain, room: room).roster.members
        #expect(
            !members.contains(mallory.identity.id),
            "Sam's answer dated Alice's removal of Mallory after his cut, and Mallory came back in")
        #expect(!members.contains(sam.identity.id))
    }

    @Test("Somebody let back in counts again from the moment they are")
    func aReturnCountsAgain() throws {
        var (alice, sam, room, entries) = try room()
        var bob = Author(chain: alice.chain)
        entries += try admit(bob.identity, by: &alice, into: room, at: start + 5)
        let said = try sam.append(try Payload.post("before"), at: start + 10, room: room)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id, heads: [said.hash]), clock: seeing(sam.feedKey, seq: said.seq),
            at: start + 20, room: room)
        let back = try admit(sam.identity, by: &bob, into: room, at: start + 30)
        let returned = try sam.append(
            try Payload.post("back again"), clock: seeing(bob.feedKey, seq: back[1].seq), at: start + 40, room: room)
        entries += [said, removal] + back + [returned]

        let result = standing(entries, chain: alice.chain, room: room)
        #expect(result.roster.members.contains(sam.identity.id), "an invitation after the removal did not bring Sam back")
        #expect(!result.out.contains(returned.hash), "what Sam said after coming back was dropped")
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
