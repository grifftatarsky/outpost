import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp
@testable import CarpenterKit

@Suite("What is unsent")
@MainActor
struct WhatIsUnsentTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    @Test("A feed read past a position gives what the log holds there, through gaps, forks and closed rooms")
    func pastAPositionMatchesTheLog() throws {
        var replica = Replica()
        var alice = Author()
        try replica.meet(alice)
        let kitchen = RoomID()
        let hangar = RoomID()

        var made: [Entry] = []
        for step in 0..<10 {
            made.append(
                try alice.append(
                    Payload.post("\(step)"), at: start.addingTimeInterval(Double(step)),
                    room: step.isMultiple(of: 3) ? kitchen : hangar))
        }
        let fork = try Entry.append(
            to: made[1], author: alice.identity.id, device: alice.device, clock: made[1].clock,
            wallTime: start, room: hangar, payload: try Payload.post("another story").sealed(at: .initial, using: alice.chain), roomLink: RoomLink(previous: nil))
        for entry in made where ![6, 8].contains(entry.seq) { try replica.integrate(entry) }
        try replica.integrate(fork)
        replica.close(kitchen)

        for position in UInt64(0)...11 {
            let expected = replica.allEntries
                .filter { $0.feedKey == alice.feedKey && $0.seq > position }
                .sorted {
                    $0.seq != $1.seq
                        ? $0.seq < $1.seq : $0.hash.rawValue.lexicographicallyPrecedes($1.hash.rawValue)
                }
            #expect(replica.entries(in: alice.feedKey, after: position) == expected, "past \(position)")
        }
    }

    @Test("A feed read past a position does not walk a sequence number nobody wrote up to")
    func aFarPositionIsNotWalked() throws {
        var replica = Replica()
        let alice = Author()
        try replica.meet(alice)
        let first = try Entry.append(
            to: nil, author: alice.identity.id, device: alice.device, clock: VectorClock(),
            wallTime: start, room: nil, payload: try Payload.post("one").sealed(at: .initial, using: alice.chain))
        try replica.integrate(first)

        let started = Date()
        #expect(replica.entries(in: alice.feedKey, after: 0) == [first])
        #expect(replica.entries(in: alice.feedKey, after: .max - 1).isEmpty)
        #expect(Date().timeIntervalSince(started) < 0.05)
    }

    @Test("Everything past the synced frontier is unsent, and nothing before it")
    func unsentStartsAtTheFrontier() throws {
        let session = TestSession.make()
        var replica = Replica()
        var alice = Author()
        try replica.meet(alice)
        for step in 0..<50 {
            try replica.integrate(
                try alice.append(Payload.post("\(step)"), at: start.addingTimeInterval(Double(step)), room: RoomID()))
        }
        session.replica = replica
        session.persisted.syncedFrontier.observe(alice.feedKey, seq: 47)

        #expect(session.unsentEntries().map(\.seq) == [48, 49, 50])
    }

    @Test("Which of my messages in a room are unsent is answered from that room, not the log")
    func unsentIsAskedOfTheRoom() {
        let viewer = ParticipantID(rawValue: WideID.of([1]))
        let device = DeviceID(rawValue: WideID.of([2]))
        let quiet = RoomID()
        let busy = RoomID()
        func entry(_ index: Int, in room: RoomID) -> RenderedEntry {
            var made = RenderedEntry(
                id: EntryHash(rawValue: WideID.of([3, UInt8(index % 256), UInt8(index / 256)])), type: .post,
                author: viewer, device: device, wallTime: Date(timeIntervalSince1970: Double(index)),
                room: room, content: .text("\(index)"), editedAt: nil, replyingTo: nil, reactions: [:])
            made.seq = UInt64(index + 1)
            return made
        }
        let rendered = (0..<5_000).map { entry($0, in: $0 < 4_990 ? busy : quiet) }
        let projected = Projection(viewer: viewer, rendered: rendered)
        var sent = VectorClock()
        sent.observe(FeedKey(author: viewer, device: device), seq: 4_995)

        #expect(projected.unsent(in: quiet, by: viewer, past: sent).count == 5)
        #expect(projected.unsent(in: quiet, by: ParticipantID(rawValue: WideID.of([9])), past: sent).isEmpty)

        let started = Date()
        for _ in 0..<200 { _ = projected.unsent(in: quiet, by: viewer, past: sent) }
        let each = Date().timeIntervalSince(started) / 200
        #expect(
            each < 0.00005,
            """
            Asking which of ten messages are unsent took \(Int(each * 1_000_000))µs beside a \
            5,000-entry log. Every open conversation asks on every draw.
            """)
    }
}
