@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Leaving a room")
struct LeavingTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func room() throws -> (alice: Author, sam: Author, room: RoomID, entries: [Entry]) {
        let chain = EpochChain.create(room: RoomID())
        var alice = Author(chain: chain.chain)
        let sam = Author(chain: chain.chain)
        let room = chain.chain.room

        var entries: [Entry] = []
        entries.append(
            try alice.append(try Payload.roomProfile(name: "Hangar 7"), at: start, room: room))
        let invite = try TestInvite.issue(
            joining: room, joinerKeys: sam.identity.publicKeys, by: alice.identity, at: start)
        entries.append(
            try alice.append(
                try Payload.joinRequest(invite), at: start.addingTimeInterval(1), room: room))
        entries.append(
            try alice.append(
                try Payload.joinConfirmed(
                    try JoinConfirmedBody.signed(confirming: invite, by: sam.identity)),
                at: start.addingTimeInterval(2), room: room))
        return (alice, sam, room, entries)
    }

    private func roster(_ entries: [Entry], _ chain: EpochChain, in room: RoomID) -> RoomRoster {
        var roster = RoomRoster(room: room)
        for rendered in Fold.render(entries, using: chain) where rendered.room == room {
            guard let payload = entries.first(where: { $0.hash == rendered.id })?.opened(using: chain)
            else { continue }
            roster.apply(rendered, body: payload)
        }
        return roster
    }

    // MARK: The roster

    @Test("Leaving takes somebody out of the room, and names nobody")
    func leavingTakesThemOut() throws {
        var (alice, sam, room, entries) = try room()
        var sam2 = sam
        entries.append(
            try sam2.append(try Payload.departure(), at: start.addingTimeInterval(10), room: room))

        let folded = roster(entries, alice.chain, in: room)
        #expect(!folded.members.contains(sam2.identity.id), "they are still counted as a member")
        #expect(folded.departure(of: sam2.identity.id) != nil, "the room does not know they left")
        #expect(
            folded.removal(of: sam2.identity.id) == nil,
            "leaving was folded as a removal, which invents a remover")
    }

    @Test("Somebody who left may not write to the room")
    func aLeaverMayNotWrite() throws {
        var (alice, sam, room, entries) = try room()
        var sam2 = sam
        entries.append(
            try sam2.append(try Payload.departure(), at: start.addingTimeInterval(10), room: room))

        #expect(!roster(entries, alice.chain, in: room).mayWrite(sam2.identity.id))
    }

    @Test("A departure from somebody who was never in the room folds to nothing")
    func aStrangerCannotLeave() throws {
        let (alice, _, room, entries) = try room()
        var stranger = Author(chain: alice.chain)
        let theirs = try stranger.append(
            try Payload.departure(), at: start.addingTimeInterval(10), room: room)

        let folded = roster(entries + [theirs], alice.chain, in: room)
        #expect(folded.departures.isEmpty, "a room announced a stranger leaving it")
    }

    @Test("Leaving twice is leaving once")
    func leavingTwiceFoldsOnce() throws {
        var (alice, sam, room, entries) = try room()
        var sam2 = sam
        entries.append(
            try sam2.append(try Payload.departure(), at: start.addingTimeInterval(10), room: room))
        entries.append(
            try sam2.append(try Payload.departure(), at: start.addingTimeInterval(20), room: room))

        let folded = roster(entries, alice.chain, in: room)
        #expect(folded.departures.count == 1)
        #expect(folded.departure(of: sam2.identity.id)?.at == start.addingTimeInterval(10))
    }

    @Test("Being asked back, and confirming again, clears the departure")
    func comingBackClearsIt() throws {
        var (alice, sam, room, entries) = try room()
        var sam2 = sam
        entries.append(
            try sam2.append(try Payload.departure(), at: start.addingTimeInterval(10), room: room))

        let again = try TestInvite.issue(
            joining: room, joinerKeys: sam2.identity.publicKeys, by: alice.identity,
            at: start.addingTimeInterval(20))
        entries.append(
            try alice.append(
                try Payload.joinRequest(again), at: start.addingTimeInterval(21), room: room))
        #expect(
            !roster(entries, alice.chain, in: room).members.contains(sam2.identity.id),
            "an invitation alone brought back somebody who had walked out")

        entries.append(
            try alice.append(
                try Payload.joinConfirmed(
                    try JoinConfirmedBody.signed(confirming: again, by: sam2.identity)),
                at: start.addingTimeInterval(22), room: room))

        let folded = roster(entries, alice.chain, in: room)
        #expect(folded.members.contains(sam2.identity.id), "they were not let back in")
        #expect(
            folded.departure(of: sam2.identity.id) == nil,
            "a member standing in the room is still being told they left it")
        #expect(folded.mayWrite(sam2.identity.id))
    }

    @Test("Replaying the invitation somebody left on lets nobody back in")
    func aSpentInvitationCannotBeReplayed() throws {
        var (alice, sam, room, entries) = try room()
        var sam2 = sam
        let spent = try #require(roster(entries, alice.chain, in: room).requests[sam2.identity.id])
        entries.append(
            try sam2.append(try Payload.departure(), at: start.addingTimeInterval(10), room: room))

        entries.append(
            try alice.append(
                try Payload.joinRequest(spent), at: start.addingTimeInterval(30), room: room))
        entries.append(
            try alice.append(
                try Payload.joinConfirmed(
                    try JoinConfirmedBody.signed(confirming: spent, by: sam2.identity)),
                at: start.addingTimeInterval(31), room: room))

        let folded = roster(entries, alice.chain, in: room)
        #expect(
            !folded.members.contains(sam2.identity.id),
            "a departure was undone by replaying the invitation it ended")
        #expect(folded.departure(of: sam2.identity.id) != nil)
    }

    // MARK: What the room draws

    private func seeing(_ key: FeedKey, seq: UInt64) -> VectorClock {
        var clock = VectorClock()
        clock.observe(key, seq: seq)
        return clock
    }

    @Test("What somebody said before leaving stays, and what they say after does not")
    func theRoomKeepsWhatWasSaidBefore() throws {
        var (alice, sam, room, entries) = try room()
        var sam2 = sam

        let before = try sam2.append(
            try Payload.post("before I left"), at: start.addingTimeInterval(10), room: room)
        let departure = try sam2.append(
            try Payload.departure(), at: start.addingTimeInterval(20), room: room)
        let after = try sam2.append(
            try Payload.post("after I left"), clock: seeing(alice.feedKey, seq: 1),
            at: start.addingTimeInterval(30), room: room)
        entries.append(contentsOf: [before, departure, after])

        let chain = alice.chain
        let projected = Projection(
            viewer: alice.identity.id, rendered: Fold.render(entries, using: chain))
        let out = projected.outOfRoom(in: room, opening: { rendered in
            entries.first { $0.hash == rendered.id }?.opened(using: chain)
        })

        let drawn = projected.messages(in: room, outOfRoom: out).map(\.body)
        #expect(drawn.contains("before I left"), "history the room already had was dropped")
        #expect(
            !drawn.contains("after I left"),
            "somebody who had left went on posting into the room")
    }

    @Test("The room is told somebody left, and no remover is named")
    func theRoomIsTold() throws {
        var (alice, sam, room, entries) = try room()
        var sam2 = sam
        entries.append(
            try sam2.append(try Payload.departure(), at: start.addingTimeInterval(10), room: room))

        let chain = alice.chain
        let projected = Projection(
            viewer: alice.identity.id, rendered: Fold.render(entries, using: chain))
        let notices = projected.transcript(
            in: room,
            opening: { rendered in entries.first { $0.hash == rendered.id }?.opened(using: chain) }
        ).compactMap { entry -> RoomNotice? in
            if case .notice(let notice) = entry { return notice }
            return nil
        }

        let left = notices.compactMap { notice -> Member? in
            if case .left(let who) = notice.kind { return who }
            return nil
        }
        #expect(left.count == 1, "the room was not told somebody left")
        #expect(left.first?.id == sam2.identity.id)
        #expect(
            !notices.contains { if case .removed = $0.kind { return true } else { return false } },
            "leaving was announced as a removal")
    }

    // MARK: Who turns the key

    @Test("The founder turns the key when somebody leaves")
    func theFounderTurnsIt() throws {
        var (alice, sam, room, entries) = try room()
        var sam2 = sam
        entries.append(
            try sam2.append(try Payload.departure(), at: start.addingTimeInterval(10), room: room))

        #expect(roster(entries, alice.chain, in: room).keyTurner == alice.identity.id)
    }

    @Test("When the founder leaves, the same remaining member turns it on every device")
    func theLowestIdentityTurnsIt() throws {
        var (alice, sam, room, entries) = try room()
        var sam2 = sam
        entries.append(
            try alice.append(try Payload.departure(), at: start.addingTimeInterval(10), room: room))

        let folded = roster(entries, alice.chain, in: room)
        #expect(folded.keyTurner == sam2.identity.id, "the room left its key to nobody")
        #expect(!folded.members.contains(alice.identity.id))
    }

    @Test("An empty room has nobody to turn its key")
    func anEmptyRoomTurnsNothing() throws {
        var (alice, sam, room, entries) = try room()
        var sam2 = sam
        entries.append(
            try sam2.append(try Payload.departure(), at: start.addingTimeInterval(10), room: room))
        entries.append(
            try alice.append(try Payload.departure(), at: start.addingTimeInterval(20), room: room))

        #expect(roster(entries, alice.chain, in: room).keyTurner == nil)
    }
}

@MainActor
@Suite("Leaving a room, from the app", .serialized)
struct SessionLeavingTests {
    private func joined() async throws -> (
        alice: AppSession, bob: AppSession, room: RoomID, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, room, mailbox)
    }

    // MARK: The Outpost-access step — ruled by Griff, 2026-09-14

    @Test("Access chosen because of a room is named when that room is left")
    func accessChosenInTheRoomIsNamed() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        let them = try #require(bob.enrolment?.identity.id)

        try await alice.allowOutpost(them, everything: true, chosenIn: room)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(
            alice.outpostAccessChosen(in: room).map(\.id) == [them],
            """
            Leaving a room has to be able to name the people who can read this member's Outpost \
            *because of* that room, or the access outlives the reason for it silently.
            """)

        let elsewhere = try await alice.createRoom(named: "Somewhere else")
        #expect(
            alice.outpostAccessChosen(in: elsewhere).isEmpty,
            "access chosen in one room was offered up while leaving a different one")
    }

    @Test("Access given for its own sake is not swept up by leaving a room")
    func accessChosenElsewhereIsLeftAlone() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        let them = try #require(bob.enrolment?.identity.id)

        try await alice.allowOutpost(them, everything: true)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(
            alice.outpostAccessChosen(in: room).isEmpty,
            """
            Leaving a room offered to end access this member gave for its own sake. The step exists \
            to stop access outliving its reason, never to quietly undo a separate decision.
            """)
    }

    @Test("Stopping on the way out ends it at today, and what was seen stays seen")
    func stoppingOnTheWayOutEndsIt() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        let them = try #require(bob.enrolment?.identity.id)

        try await alice.allowOutpost(them, everything: true, chosenIn: room)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        try #require(alice.outpostReaders().contains(them))

        try await alice.revokeOutpost(them, chosenIn: room)
        try await alice.leave(room)
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(
            !alice.outpostReaders().contains(them),
            "leaving the room and stopping their access left them still reading the Outpost")
        #expect(
            alice.outpostAccessChosen(in: room).isEmpty,
            "the person still appears as holding access chosen in a room already left")
    }

    @Test("Leaving tells the room, and the leaver's own copy says so")
    func leavingTellsTheRoom() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        let them = try #require(bob.enrolment?.identity.id)
        try #require(alice.roster(of: room).members.contains(them))

        try await bob.leave(room)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        #expect(bob.standing(in: room) == .left)
        #expect(alice.standing(in: room) == .present)
        #expect(
            !alice.roster(of: room).members.contains(them),
            "the room still counts somebody who left as a member")
    }

    @Test("Everybody else sees a line saying they left")
    func theRoomSeesTheLine() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        try await bob.leave(room)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        let said = alice.transcript(in: room).compactMap { entry -> RoomNotice.Kind? in
            if case .notice(let notice) = entry { return notice.kind }
            return nil
        }
        #expect(
            said.contains { if case .left = $0 { return true } else { return false } },
            "the room was never told")
    }

    @Test("A member who left cannot write, and is not told they were removed")
    func aLeaverCannotWrite() async throws {
        let (_, bob, room, _) = try await joined()
        try await bob.leave(room)

        await #expect(throws: MembershipError.leftThisRoom) {
            try await bob.send("still here", to: room)
        }
    }

    @Test("Somebody who remains turns the key, and the leaver does not")
    func theRoomTurnsItsKey() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        let before = try #require(alice.epoch(of: room))

        try await bob.leave(room)
        try await bob.sync(through: mailbox)
        #expect(
            bob.epoch(of: room) == before,
            "the member who left turned the key, so they hold what comes next")

        try await alice.sync(through: mailbox)
        #expect(
            try #require(alice.epoch(of: room)) > before,
            "nobody turned the key after somebody left")
    }

    @Test("The key turns once, however often the room syncs afterwards")
    func theKeyTurnsOnce() async throws {
        let (alice, bob, room, mailbox) = try await joined()

        try await bob.leave(room)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        let turned = try #require(alice.epoch(of: room))

        try await alice.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        #expect(alice.epoch(of: room) == turned, "the key turned again for a departure already answered")
    }
}
