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

        mutating func writeHidingWhatWasRead(
            _ payload: Payload, by author: WritableKeyPath<Room, Author>, at time: Date
        ) throws -> Entry {
            let writer = self[keyPath: author]
            let entry = try Entry.append(
                to: writer.head, author: writer.identity.id, device: writer.device, clock: VectorClock(),
                wallTime: time, room: room, payload: payload, at: .initial, sealedWith: writer.chain,
                roomLink: RoomLink(previous: writer.roomHeads[room]))
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

        var projected: Projection { projected(by: founder.identity.id) }

        func projected(by viewer: ParticipantID, reading times: [EntryHash: Date] = [:]) -> Projection {
            Projection(
                viewer: viewer, rendered: LogRenderer.render(entries, using: founder.chain),
                chains: RoomChains(entries), claimTimes: times)
        }

        func opening(_ rendered: RenderedEntry) -> Payload? {
            entries.first { $0.hash == rendered.id }?.opened(using: founder.chain)
        }

        var out: Set<EntryHash> { projected.outOfRoom(in: room, opening: opening) }
        var members: Set<ParticipantID> { projected.roster(of: room, opening: opening).members }

        mutating func malloryRemovesVicWhoKeepsTalking(at time: Date) throws -> (after: Entry, seeing: VectorClock) {
            let removal = try write(
                try Payload.removal(of: vic.identity.id, heads: []), by: \.mallory, clock: seeing(vic), at: time)
            var clock = seeing(vic)
            clock.observe(removal.feedKey, seq: removal.seq)
            let after = try write(try Payload.post("still here"), by: \.vic, clock: clock, at: time + 10)
            clock.observe(after.feedKey, seq: after.seq)
            return (after, clock)
        }
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

    @Test("A removed member cannot bring back what they wrote after their removal by removing the founder")
    func aRemovedMemberCannotUndoTheirOwnRemoval() throws {
        var r = try room()
        let removal = try r.write(
            try Payload.removal(of: r.vic.identity.id, heads: []), by: \.mallory, clock: r.seeing(r.vic), at: start + 20)
        var afterTheRemoval = r.seeing(r.vic)
        afterTheRemoval.observe(removal.feedKey, seq: removal.seq)
        let after = try r.write(try Payload.post("still here"), by: \.vic, clock: afterTheRemoval, at: start + 30)
        try #require(r.out.contains(after.hash), "precondition: what Vic wrote after his removal is out")

        afterTheRemoval.observe(after.feedKey, seq: after.seq)
        _ = try r.write(
            try Payload.removal(of: r.founder.identity.id, heads: []), by: \.vic, clock: afterTheRemoval, at: start + 31)

        #expect(
            r.out.contains(after.hash),
            "one removal of the founder, written by somebody already removed, put their post-removal words back in the room")
        #expect(r.members.contains(r.founder.identity.id), "precondition: Vic's removal of the founder did nothing")
    }

    @Test("A removed member cannot undo their removal by cutting only the invitation that let the remover in")
    func aRemovedMemberCannotCutTheirRemoversWayIn() throws {
        var r = try room()
        let (after, seeing) = try r.malloryRemovesVicWhoKeepsTalking(at: start + 20)
        let throughVicsOwnInvitation = r.entries[2]
        _ = try r.write(
            try Payload.removal(of: r.founder.identity.id, heads: [throughVicsOwnInvitation.hash]), by: \.vic,
            clock: seeing, at: start + 31)

        #expect(r.out.contains(after.hash), "cutting the founder's invitation of the remover put the removed member's words back")
        #expect(r.members.contains(r.mallory.identity.id), "the removed member's answer took the remover out")
        #expect(r.members.contains(r.founder.identity.id))
        #expect(!r.members.contains(r.vic.identity.id))
    }

    @Test("A removed member who removes the remover after reading their own removal stays out, whichever a phone read first")
    func aRemovedMemberCannotRemoveTheRemover() throws {
        var r = try room()
        let (after, seeing) = try r.malloryRemovesVicWhoKeepsTalking(at: start + 20)
        let answer = try r.write(
            try Payload.removal(of: r.mallory.identity.id, heads: []), by: \.vic, clock: seeing, at: start + 31)
        let removal = try #require(r.entries.first { $0.author == r.mallory.identity.id && $0.wallTime == start + 20 })

        for (viewer, times) in [
            (r.founder.identity.id, [EntryHash: Date]()),
            (r.vic.identity.id, [answer.hash: start, removal.hash: start + 100]),
        ] {
            let projected = r.projected(by: viewer, reading: times)
            #expect(
                projected.outOfRoom(in: r.room, opening: r.opening).contains(after.hash),
                "the removed member's words came back on a phone that read their answer first")
            #expect(projected.roster(of: r.room, opening: r.opening).members.contains(r.mallory.identity.id))
        }
    }

    @Test("A removed member who hides that they had read their removal still cannot undo it by removing the founder")
    func aRemovedMemberCannotPretendNotToHaveSeenIt() throws {
        var r = try room()
        let (after, _) = try r.malloryRemovesVicWhoKeepsTalking(at: start + 20)
        _ = try r.writeHidingWhatWasRead(try Payload.removal(of: r.founder.identity.id, heads: []), by: \.vic, at: start + 31)

        #expect(r.out.contains(after.hash), "a removal of the founder that claimed not to have seen the removal undid it")
        #expect(r.members.contains(r.founder.identity.id))
    }

    @Test("A removed member who hides that they had read their removal and cuts only the remover's invitation is the open question")
    func aHiddenReadingAndANarrowCutAreStillOpen() throws {
        var r = try room()
        let (after, _) = try r.malloryRemovesVicWhoKeepsTalking(at: start + 20)
        _ = try r.writeHidingWhatWasRead(
            try Payload.removal(of: r.founder.identity.id, heads: [r.entries[2].hash]), by: \.vic, at: start + 31)

        withKnownIssue("a removal that names nothing of what its author read: open-questions.md") {
            #expect(r.out.contains(after.hash))
        }
    }

    @Test("A removed member's removal of the founder does not undo somebody else leaving")
    func aRemovedMemberCannotUndoSomebodyLeaving() throws {
        var r = try room()
        let (after, seeing) = try r.malloryRemovesVicWhoKeepsTalking(at: start + 20)
        let left = try r.write(try Payload.departure(heads: []), by: \.sam, at: start + 25)
        var sinceLeaving = VectorClock()
        sinceLeaving.observe(left.feedKey, seq: left.seq)
        let afterLeaving = try r.write(try Payload.post("gone"), by: \.sam, clock: sinceLeaving, at: start + 26)
        _ = try r.write(
            try Payload.removal(of: r.founder.identity.id, heads: []), by: \.vic, clock: seeing, at: start + 31)

        #expect(r.out.contains(after.hash))
        #expect(r.out.contains(afterLeaving.hash), "what somebody wrote after leaving came back")
        #expect(!r.members.contains(r.sam.identity.id), "somebody who left was counted in again")
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
