@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("What a room draws after a removal")
struct RemovedMemberRenderingTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func seeing(_ key: FeedKey, seq: UInt64) -> VectorClock {
        var clock = VectorClock()
        clock.observe(key, seq: seq)
        return clock
    }

    private func room() throws -> (alice: Author, sam: Author, room: ConversationID, entries: [Entry]) {
        let chain = EpochChain.create(room: ConversationID.room(UUID()))
        var alice = Author(chain: chain.chain)
        var sam = Author(chain: chain.chain)
        let room = chain.chain.room

        var entries: [Entry] = []
        entries.append(
            try alice.append(try Payload.roomProfile(name: "Hangar 7"), at: start, room: room))
        let invite = try TestInvite.issue(
            joining: room, joinerKeys: sam.identity.publicKeys, by: alice.identity, at: start)
        entries.append(
            try alice.append(try Payload.joinRequest(invite), at: start.addingTimeInterval(1), room: room))
        entries.append(
            try alice.append(
                try Payload.joinConfirmed(
                    try JoinConfirmedBody.signed(confirming: invite, by: sam.identity)),
                at: start.addingTimeInterval(2), room: room))
        return (alice, sam, room, entries)
    }

    @Test("A room does not draw what a removed member said after they were removed")
    func aRoomDoesNotDrawWhatARemovedMemberSaidAfterwards() throws {
        var (alice, sam, room, entries) = try room()
        let chain = alice.chain

        let before = try sam.append(
            try Payload.post("before the removal"), at: start.addingTimeInterval(10), room: room)
        entries.append(before)

        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id),
            clock: seeing(sam.feedKey, seq: before.seq),
            at: start.addingTimeInterval(20), room: room)
        entries.append(removal)

        let after = try sam.append(
            try Payload.post("after the removal"),
            clock: seeing(alice.feedKey, seq: removal.seq),
            at: start.addingTimeInterval(30), room: room)
        entries.append(after)

        let projected = Projection(
            viewer: alice.identity.id, rendered: Fold.render(entries, using: chain))
        let opener: (RenderedEntry) -> Payload? = { rendered in
            entries.first { $0.hash == rendered.id }?.opened(using: chain)
        }
        let out = projected.outOfRoom(in: room, opening: opener)

        #expect(out.contains(after.hash), "the room still counted what they said after removal")
        #expect(!out.contains(before.hash), "a message written before the removal was suppressed")

        let drawn = projected.messages(in: room, outOfRoom: out).map(\.body)
        #expect(drawn.contains("before the removal"), "history the room already had was dropped")
        #expect(
            !drawn.contains("after the removal"),
            "a removed member's message rendered as an ordinary one")
    }

    @Test("A removal touches nothing written before it")
    func aRemovalTouchesNothingBeforeIt() throws {
        var (alice, sam, room, entries) = try room()
        let chain = alice.chain

        var theirs: [Entry] = []
        for i in 1...3 {
            let e = try sam.append(
                try Payload.post("said \(i)"), at: start.addingTimeInterval(Double(i)), room: room)
            theirs.append(e)
            entries.append(e)
        }
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id),
            clock: seeing(sam.feedKey, seq: theirs.last!.seq),
            at: start.addingTimeInterval(20), room: room)
        entries.append(removal)

        let projected = Projection(
            viewer: alice.identity.id, rendered: Fold.render(entries, using: chain))
        let out = projected.outOfRoom(in: room, opening: { rendered in
            entries.first { $0.hash == rendered.id }?.opened(using: chain)
        })

        for e in theirs {
            #expect(!out.contains(e.hash), "history the removal was made in light of stopped drawing")
        }
        let drawn = projected.messages(in: room, outOfRoom: out).map(\.body)
        #expect(drawn == ["said 1", "said 2", "said 3"], "the room stopped drawing its own history")
    }

    @Test("A backdated wall clock does not put a removed member back in the room")
    func aBackdatedClockDoesNotRestoreThem() throws {
        var (alice, sam, room, entries) = try room()
        let chain = alice.chain

        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id),
            at: start.addingTimeInterval(100), room: room)
        entries.append(removal)

        let backdated = try sam.append(
            try Payload.post("stamped in the past"),
            clock: seeing(alice.feedKey, seq: removal.seq),
            at: start.addingTimeInterval(-3600), room: room)
        entries.append(backdated)

        let projected = Projection(
            viewer: alice.identity.id, rendered: Fold.render(entries, using: chain))
        let out = projected.outOfRoom(in: room, opening: { rendered in
            entries.first { $0.hash == rendered.id }?.opened(using: chain)
        })

        #expect(
            out.contains(backdated.hash),
            "a backdated wall clock let a removed member write into the room")
    }

    @Test("The removed member keeps their own copy of what did not go")
    func theirOwnCopyKeepsIt() throws {
        var (alice, sam, room, entries) = try room()
        let chain = alice.chain

        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id),
            at: start.addingTimeInterval(20), room: room)
        entries.append(removal)
        let after = try sam.append(
            try Payload.post("still mine"),
            clock: seeing(alice.feedKey, seq: removal.seq),
            at: start.addingTimeInterval(30), room: room)
        entries.append(after)

        let opener: (RenderedEntry) -> Payload? = { rendered in
            entries.first { $0.hash == rendered.id }?.opened(using: chain)
        }

        let onAlice = Projection(
            viewer: alice.identity.id, rendered: Fold.render(entries, using: chain))
        let outOnAlice = onAlice.outOfRoom(in: room, opening: opener)
        #expect(!onAlice.messages(in: room, outOfRoom: outOnAlice).map(\.body).contains("still mine"))

        let onSam = Projection(
            viewer: sam.identity.id, rendered: Fold.render(entries, using: chain))
        let outOnSam = onSam.outOfRoom(in: room, opening: opener)
        #expect(
            onSam.messages(in: room, outOfRoom: outOnSam).map(\.body).contains("still mine"),
            "the app took away something the removed member wrote and still holds")
    }

    @Test("A message the room does not draw is still held and still folded")
    func stillHeldStillFolded() throws {
        var (alice, sam, room, entries) = try room()
        let chain = alice.chain

        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id),
            at: start.addingTimeInterval(20), room: room)
        entries.append(removal)
        let after = try sam.append(
            try Payload.post("held anyway"),
            clock: seeing(alice.feedKey, seq: removal.seq),
            at: start.addingTimeInterval(30), room: room)
        entries.append(after)

        let rendered = Fold.render(entries, using: chain)
        #expect(
            rendered.contains { $0.id == after.hash },
            "the fold dropped an entry rather than declining to draw it")

        var replica = Replica()
        replica.introduce(alice.identity.publicKeys)
        replica.introduce(sam.identity.publicKeys)
        try replica.admit(alice.certificate)
        try replica.admit(sam.certificate)
        for entry in entries { _ = try replica.integrate(entry) }
        #expect(
            replica.allEntries.contains { $0.hash == after.hash },
            "an entry the room does not draw was refused at storage, which §8.1 forbids")
    }

    @Test("Every device reaches the same verdict, whatever order the entries arrived in")
    func theVerdictIsOrderIndependent() throws {
        var (alice, sam, room, entries) = try room()
        let chain = alice.chain

        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id),
            at: start.addingTimeInterval(20), room: room)
        entries.append(removal)
        entries.append(
            try sam.append(
                try Payload.post("one"),
                clock: seeing(alice.feedKey, seq: removal.seq),
                at: start.addingTimeInterval(30), room: room))
        entries.append(
            try sam.append(try Payload.post("two"), at: start.addingTimeInterval(40), room: room))
        #expect(entries.filter { $0.conversation == room }.count == 6)

        func verdict(_ order: [Entry]) -> Set<EntryHash> {
            let projected = Projection(
                viewer: alice.identity.id, rendered: Fold.render(order, using: chain))
            return projected.outOfRoom(in: room, opening: { rendered in
                order.first { $0.hash == rendered.id }?.opened(using: chain)
            })
        }

        let forwards = verdict(entries)
        let backwards = verdict(entries.reversed())
        let jumbled = verdict(Array(entries.suffix(2) + entries.prefix(entries.count - 2)))

        #expect(!forwards.isEmpty, "the test proved nothing — nobody was out of the room")
        #expect(forwards == backwards, "two devices disagreed about who was in the room")
        #expect(forwards == jumbled, "the verdict depended on arrival order")
    }
}
