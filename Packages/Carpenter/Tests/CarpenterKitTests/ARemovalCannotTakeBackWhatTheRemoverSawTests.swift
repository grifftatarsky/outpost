@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("A removal cannot take back what the remover had seen")
struct ARemovalCannotTakeBackWhatTheRemoverSawTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private struct Room {
        var founder: Author
        var vic: Author
        var mallory: Author
        var sam: Author
        let room: RoomID
        var entries: [Entry]

        func seeing(_ authors: Author...) -> VectorClock {
            var clock = VectorClock()
            for author in authors { if let head = author.head { clock.observe(author.feedKey, seq: head.seq) } }
            return clock
        }

        mutating func write(_ payload: Payload, by author: WritableKeyPath<Room, Author>, clock: VectorClock = VectorClock(), at time: Date) throws -> Entry {
            let entry = try self[keyPath: author].append(payload, clock: clock, at: time, room: room)
            entries.append(entry)
            return entry
        }

        mutating func invite(_ joiner: Identity, by inviter: WritableKeyPath<Room, Author>, at time: Date) throws -> MembershipAttestation {
            let invite = try TestInvite.issue(
                joining: room, joinerKeys: joiner.publicKeys, by: self[keyPath: inviter].identity, at: time)
            _ = try write(try Payload.joinRequest(invite), by: inviter, at: time)
            _ = try write(
                try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: joiner)), by: inviter,
                at: time + 1)
            return invite
        }

        var projected: Projection {
            Projection(
                viewer: founder.identity.id, rendered: LogRenderer.render(entries, using: founder.chain),
                chains: RoomChains(entries))
        }

        func opening(_ rendered: RenderedEntry) -> Payload? {
            entries.first { $0.hash == rendered.id }?.opened(using: founder.chain)
        }

        var out: Set<EntryHash> { projected.outOfRoom(in: room, opening: opening) }
        var members: Set<ParticipantID> { projected.roster(of: room, opening: opening).members }
    }

    private func room(access: RoomAccess = .open) throws -> Room {
        let (founder, room, profile) = try Author.founding()
        var made = Room(
            founder: founder, vic: Author(chain: founder.chain), mallory: Author(chain: founder.chain),
            sam: Author(chain: founder.chain), room: room, entries: [])
        _ = try made.write(profile, by: \.founder, at: start)
        if access != .open { _ = try made.write(try Payload.roomAccess(access), by: \.founder, at: start) }
        for joiner in [made.vic.identity, made.mallory.identity, made.sam.identity] {
            let invite = try made.invite(joiner, by: \.founder, at: start + 1)
            if access != .open {
                _ = try made.write(
                    try Payload.admission(of: joiner.id, admitted: true, invitation: invite.signature), by: \.founder,
                    at: start + 2)
            }
        }
        return made
    }

    @Test("A removal that names nothing keeps what the remover's phone had already marked as read")
    func whatTheRemoverReadStays() throws {
        var r = try room()
        let read = try r.write(try Payload.post("seen"), by: \.vic, at: start + 10)
        _ = try r.write(try Payload.readReceipt(upTo: read.hash), by: \.mallory, clock: r.seeing(r.vic), at: start + 11)
        _ = try r.write(try Payload.removal(of: r.vic.identity.id, heads: []), by: \.mallory, clock: r.seeing(r.vic), at: start + 20)
        let after = try r.write(try Payload.post("after"), by: \.vic, at: start + 5)
        _ = try r.write(try Payload.readReceipt(upTo: after.hash), by: \.mallory, clock: r.seeing(r.vic), at: start + 30)

        #expect(!r.out.contains(read.hash), "a removal naming nothing took back a message the remover's phone had read")
        #expect(r.out.contains(after.hash), "something written after the removal counted because the remover read it later")
        #expect(!r.members.contains(r.vic.identity.id), "precondition: the removal took")
    }

    @Test("A removal that names nothing cannot undo an invitation another member had already answered")
    func anAnsweredInvitationStays() throws {
        var r = try room(access: .anyMember)
        let ann = Identity.generate()
        let invite = try r.invite(ann, by: \.vic, at: start + 10)
        _ = try r.write(
            try Payload.admission(of: ann.id, admitted: true, invitation: invite.signature), by: \.founder,
            clock: r.seeing(r.vic), at: start + 12)
        try #require(r.members.contains(ann.id), "precondition: Ann was let in")

        _ = try r.write(
            try Payload.removal(of: r.vic.identity.id, heads: []), by: \.mallory, clock: r.seeing(r.vic, r.founder),
            at: start + 20)

        #expect(r.members.contains(ann.id), "removing the member who invited Ann put her out, with nothing saying so")
        #expect(!r.members.contains(r.vic.identity.id), "precondition: the removal took")
    }

    @Test("Leaving cannot take back what the leaver's own phone wrote before it")
    func aDepartureKeepsItsOwnPast() throws {
        var r = try room()
        let said = try r.write(try Payload.post("said before leaving"), by: \.vic, at: start + 10)
        let ann = Identity.generate()
        _ = try r.invite(ann, by: \.vic, at: start + 11)
        try #require(r.members.contains(ann.id), "precondition: Ann was let in")

        _ = try r.write(try Payload.departure(heads: []), by: \.vic, at: start + 20)

        #expect(!r.out.contains(said.hash), "leaving with a departure that names nothing erased what the leaver had said")
        #expect(r.members.contains(ann.id), "leaving put out everybody the leaver had let in")
        #expect(!r.members.contains(r.vic.identity.id), "precondition: Vic left")
    }

    @Test("A confirmation passed on by somebody already removed does not count as answering an invitation")
    func aRemovedMembersAnswerDoesNotCount() throws {
        var r = try room()
        _ = try r.write(try Payload.removal(of: r.sam.identity.id, heads: []), by: \.founder, at: start + 5)
        let puppet = Identity.generate()
        let invite = try TestInvite.issue(joining: r.room, joinerKeys: puppet.publicKeys, by: r.vic.identity, at: start + 10)
        let confirmation = try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: puppet))
        _ = try r.write(try Payload.joinRequest(invite), by: \.vic, at: start + 10)
        _ = try r.write(confirmation, by: \.vic, at: start + 11)
        _ = try r.write(confirmation, by: \.sam, at: start + 12)

        _ = try r.write(
            try Payload.removal(of: r.vic.identity.id, heads: []), by: \.mallory, clock: r.seeing(r.vic), at: start + 20)

        #expect(
            !r.members.contains(puppet.id),
            "something Sam wrote after his own removal kept an invitation from somebody else's removal")
    }
}
