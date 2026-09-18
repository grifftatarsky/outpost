import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Room notices", .serialized)
@MainActor
struct RoomNoticeTests {
    private func pair(_ mailbox: any Mailbox) async throws
        -> (alice: AppSession, bob: AppSession, room: RoomID)
    {
        let clock = TestClock(now: TestSession.now)
        let alice = AppSession(storage: TestSession.storage(), clock: clock)
        let bob = AppSession(storage: TestSession.storage(), clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<5 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, room)
    }

    private func notices(_ session: AppSession, _ room: RoomID) -> [RoomNotice.Kind] {
        session.transcript(in: room).compactMap {
            if case .notice(let notice) = $0 { return notice.kind }
            return nil
        }
    }

    @Test("Naming a room announces it once, and renaming announces the new name")
    func creationAndRename() async throws {
        let mailbox = InMemoryMailbox()
        let (alice, _, room) = try await pair(mailbox)

        let created = notices(alice, room)
        #expect(created.count == 3, "the room was started, somebody was invited, and they confirmed")
        guard case .created(let by, let named) = created.first else {
            Issue.record("the first notice was not the room being started: \(created)")
            return
        }
        #expect(by.displayName == "Alice")
        #expect(named == "Hangar 7")
    }

    @Test("An invitation and the arrival are announced as the two things they are")
    func invitingAndArriving() async throws {
        let mailbox = InMemoryMailbox()
        let (alice, bob, room) = try await pair(mailbox)

        for kinds in [notices(alice, room), notices(bob, room)] {
            guard let invited = kinds.compactMap({ kind -> (Member, Member)? in
                if case .invited(let who, let by) = kind { return (who, by) }
                return nil
            }).first else {
                Issue.record("nobody was announced as invited: \(kinds)")
                return
            }
            #expect(invited.0.displayName == "Bob")
            #expect(invited.1.displayName == "Alice")

            guard let confirmed = kinds.compactMap({ kind -> Member? in
                if case .confirmed(let who) = kind { return who }
                return nil
            }).first else {
                Issue.record("nobody was announced as having confirmed: \(kinds)")
                return
            }
            #expect(confirmed.displayName == "Bob")

            #expect(
                !kinds.contains { if case .admitted = $0 { return true } else { return false } },
                "an open room announced an admission nobody made")
        }
    }

    @Test("Both members see the same transcript")
    func bothEndsAgree() async throws {
        let mailbox = InMemoryMailbox()
        let (alice, bob, room) = try await pair(mailbox)

        try await alice.send("hello", to: room)
        for _ in 0..<3 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(alice.transcript(in: room).map(\.id) == bob.transcript(in: room).map(\.id))
    }

    @Test("Receipts and policies are not announced")
    func machineryStaysHidden() async throws {
        let mailbox = InMemoryMailbox()
        let (alice, bob, room) = try await pair(mailbox)

        try await alice.send("hello", to: room)
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        if let message = bob.messages(in: room).first(where: { !$0.isMine }) {
            await bob.markSeen(message.id, in: room)
        }
        await bob.setReportsDisplaying(true)
        for _ in 0..<3 {
            try await bob.sync(through: mailbox)
            try await alice.sync(through: mailbox)
        }

        let kinds = notices(alice, room)
        #expect(kinds.count == 3, "something that is not a room event was announced: \(kinds)")
    }

    @Test("A notice breaks a run of messages")
    func noticesBreakRuns() {
        let author = Member(id: ParticipantID(rawValue: WideID.of([1])), displayName: "Alice")
        func message(_ text: String, at offset: TimeInterval) -> Message {
            Message(
                id: MessageID(entry: EntryHash(rawValue: Data(text.utf8))),
                author: author, body: text, sentAt: TestSession.now.addingTimeInterval(offset),
                isMine: true)
        }

        let notice = RoomNotice(
            id: EntryHash(rawValue: Data([9])),
            kind: .invited(
                Member(id: ParticipantID(rawValue: WideID.of([2])), displayName: "Bob"), by: author),
            at: TestSession.now.addingTimeInterval(1))

        let items = ConversationLayout.items(from: [
            .message(message("before", at: 0)),
            .notice(notice),
            .message(message("after", at: 2)),
        ])

        #expect(items.count == 3, "the two messages were grouped across the notice")
        guard case .run(let first) = items.first, case .run(let last) = items.last else {
            Issue.record("the transcript did not begin and end with a run: \(items)")
            return
        }
        #expect(first.messages.count == 1)
        #expect(last.messages.count == 1)
    }

    @Test("The room says who took the invitation back, not who offered it")
    func aWithdrawalNamesWhoeverDidIt() throws {
        let room = RoomID()
        var alice = Author()
        var bob = Author(chain: alice.chain)
        let joiner = Identity.generate()

        let invitation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: alice.identity, at: TestSession.now,
            lasting: .aWeek)

        let entries = [
            try alice.append(try Payload.roomProfile(name: "Hangar 7"), at: TestSession.now, room: room),
            try alice.append(
                try Payload.joinRequest(invitation), at: TestSession.now.addingTimeInterval(60),
                room: room),
            try bob.append(
                try Payload.invitationRescinded(of: invitation),
                at: TestSession.now.addingTimeInterval(120), room: room),
        ]

        let projection = Projection(
            viewer: alice.identity.id, rendered: Fold.render(entries, using: alice.chain))
        let kinds = projection.transcript(
            in: room,
            opening: { rendered in
                entries.first { $0.hash == rendered.id }?.opened(using: alice.chain)
            }
        ).compactMap { entry -> RoomNotice.Kind? in
            if case .notice(let notice) = entry { return notice.kind }
            return nil
        }

        guard let (who, by) = kinds.compactMap({ kind -> (Member, Member)? in
            if case .tookBackInvitation(let who, let by) = kind { return (who, by) }
            return nil
        }).first else {
            Issue.record("the room said nothing about the invitation being taken back: \(kinds)")
            return
        }

        #expect(who.id == joiner.id)
        #expect(
            by.id == bob.identity.id,
            "the room credited the withdrawal to whoever made the offer instead of whoever took it back")
    }
}
