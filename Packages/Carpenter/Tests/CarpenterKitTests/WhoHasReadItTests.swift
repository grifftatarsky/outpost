import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("Who has read a message", .serialized)
struct WhoHasReadItTests {
    private func room(of size: Int) async throws -> (
        host: AppSession, others: [AppSession], room: ConversationID, mailbox: InMemoryMailbox,
        clock: TestClock
    ) {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let host = TestSession.make(clock: clock)
        let others = (0..<size).map { _ in TestSession.make(clock: clock) }
        for session in [host] + others { await session.load() }
        try await host.createIdentity(displayName: "Griff")
        for (index, other) in others.enumerated() {
            try await other.createIdentity(displayName: "Reader \(index + 1)")
        }

        let room = try await host.createRoom(named: "Kitchen")
        for other in others {
            let invite = try await host.invite(
                joinerCode: other.identityCode(), joining: room, mailbox: nil)
            try await other.redeem(inviteCode: try invite.encoded())
            try await host.sync(through: mailbox)
            try await other.accept(
                invite.attestation, from: try #require(host.enrolment?.identity.publicKeys))
            try await settle([host] + others, through: mailbox)
        }
        return (host, others, room, mailbox, clock)
    }

    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    @Test("Nobody reports by default, and the screen says that rather than waiting")
    func nobodyReportsByDefault() async throws {
        let (host, others, room, mailbox, _) = try await room(of: 2)
        try await host.send("the tap is dripping again", to: room)
        try await settle([host] + others, through: mailbox)

        let message = try #require(host.messages(in: room).first)
        let readers = host.readBy(message.id, in: room)

        #expect(readers.count == 2, "the list did not name everybody else in the room")
        #expect(
            readers.allSatisfy { $0.report == .doesNotReport },
            """
            Somebody was shown as not having read it yet when in fact they will never report. \
            Read receipts are off by default — Griff, 2026-09-12 — so "does not report" is the \
            answer, not a wait.
            """)
    }

    @Test("Somebody who reports shows the time their device displayed it")
    func somebodyWhoReportsShowsATime() async throws {
        let (host, others, room, mailbox, clock) = try await room(of: 2)
        let reader = others[0]
        await reader.setReportsDisplaying(true)
        try await settle([host] + others, through: mailbox)

        try await host.send("the tap is dripping again", to: room)
        try await settle([host] + others, through: mailbox)

        clock.advance(by: 300)
        let theirs = try #require(reader.messages(in: room).first { !$0.isMine })
        await reader.markSeen(theirs.id, in: room)
        try await settle([host] + others, through: mailbox)

        let message = try #require(host.messages(in: room).first { $0.isMine })
        let readers = host.readBy(message.id, in: room)
        let who = try #require(readers.first { $0.member.id == reader.enrolment?.identity.id })

        #expect(who.report.wasDisplayed, "a reader who reported was not shown as having seen it")
        if case .displayed(let at) = who.report {
            #expect(
                at == TestSession.now.addingTimeInterval(300),
                "the time shown is not when the receipt was written")
        }

        let silent = try #require(readers.first { $0.member.id == others[1].enrolment?.identity.id })
        #expect(
            silent.report == .doesNotReport,
            "somebody with receipts off was folded in with the reader who has them on")
    }

    @Test("A message nobody has reached yet says nothing yet, not nothing")
    func aMessageNobodyHasReachedSaysNothingYet() async throws {
        let (host, others, room, mailbox, _) = try await room(of: 1)
        let reader = others[0]
        await reader.setReportsDisplaying(true)
        try await settle([host] + others, through: mailbox)

        try await host.send("first", to: room)
        try await settle([host] + others, through: mailbox)
        let first = try #require(reader.messages(in: room).first { !$0.isMine })
        await reader.markSeen(first.id, in: room)
        try await settle([host] + others, through: mailbox)

        try await host.send("second, unread", to: room)
        try await settle([host] + others, through: mailbox)

        let second = try #require(
            host.messages(in: room).first { $0.body == "second, unread" })
        let who = try #require(host.readBy(second.id, in: room).first)

        #expect(
            who.report == .nothingYet,
            """
            A reader whose cursor has not reached this message was reported as something other \
            than waiting. Their receipt covers an earlier message only.
            """)
    }

    @Test("A solo lists the one person and nobody else")
    func aSoloListsTheOnePerson() async throws {
        let (host, others, room, mailbox, _) = try await room(of: 1)
        try await host.send("just us", to: room)
        try await settle([host] + others, through: mailbox)

        let message = try #require(host.messages(in: room).first)
        #expect(
            host.readBy(message.id, in: room).count == 1,
            "a two-person conversation listed more than the one person who could read it")
    }

    @Test("This member is never in their own list")
    func thisMemberIsNeverInTheirOwnList() async throws {
        let (host, others, room, mailbox, _) = try await room(of: 2)
        try await host.send("the tap is dripping again", to: room)
        try await settle([host] + others, through: mailbox)

        let message = try #require(host.messages(in: room).first)
        #expect(
            host.readBy(message.id, in: room)
                .allSatisfy { $0.member.id != host.enrolment?.identity.id },
            "the sender was listed among the people who might have read their own message")
    }

    @Test("Readers come back shown first, then waiting, then the ones who will not say")
    func readersComeBackInAUsefulOrder() async throws {
        let (host, others, room, mailbox, clock) = try await room(of: 3)
        await others[0].setReportsDisplaying(true)
        await others[1].setReportsDisplaying(true)
        try await settle([host] + others, through: mailbox)

        try await host.send("the tap is dripping again", to: room)
        try await settle([host] + others, through: mailbox)

        clock.advance(by: 60)
        let theirs = try #require(others[0].messages(in: room).first { !$0.isMine })
        await others[0].markSeen(theirs.id, in: room)
        try await settle([host] + others, through: mailbox)

        let message = try #require(host.messages(in: room).first { $0.isMine })
        let reports = host.readBy(message.id, in: room).map(\.report)

        #expect(reports.first?.wasDisplayed == true, "somebody who has seen it is not listed first")
        #expect(
            reports.last == .doesNotReport,
            "the people who will never report should sit at the bottom, not among the waiting")
    }
}

@MainActor
@Suite("Reporting can differ from room to room", .serialized)
struct PerRoomReportingTests {
    private func twoRooms() async throws -> (
        host: AppSession, reader: AppSession, kitchen: ConversationID, hangar: ConversationID,
        mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let host = TestSession.make(clock: clock)
        let reader = TestSession.make(clock: clock)
        for session in [host, reader] { await session.load() }
        try await host.createIdentity(displayName: "Griff")
        try await reader.createIdentity(displayName: "Outie")

        var made: [ConversationID] = []
        for name in ["Kitchen", "Hangar"] {
            let room = try await host.createRoom(named: name)
            let invite = try await host.invite(
                joinerCode: reader.identityCode(), joining: room, mailbox: nil)
            try await reader.redeem(inviteCode: try invite.encoded())
            try await host.sync(through: mailbox)
            try await reader.accept(
                invite.attestation, from: try #require(host.enrolment?.identity.publicKeys))
            for _ in 0..<6 {
                for session in [host, reader] {
                    try await session.sync(through: mailbox, media: mailbox)
                }
            }
            made.append(room)
        }
        return (host, reader, made[0], made[1], mailbox)
    }

    private func settle(_ everyone: [AppSession], through mailbox: InMemoryMailbox) async throws {
        for _ in 0..<6 {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    @Test("A room with no answer of its own follows the member's usual one")
    func aRoomWithNoAnswerFollowsTheUsualOne() async throws {
        let (_, reader, kitchen, _, _) = try await twoRooms()

        #expect(reader.reportsDisplayingAnswer(for: kitchen) == nil)
        #expect(!reader.isReportingDisplaying(in: kitchen))

        await reader.setReportsDisplaying(true)
        #expect(
            reader.isReportingDisplaying(in: kitchen),
            "turning reporting on everywhere did not reach a room that had said nothing")
    }

    @Test("A room can report while the rest do not")
    func aRoomCanReportWhileTheRestDoNot() async throws {
        let (host, reader, kitchen, hangar, mailbox) = try await twoRooms()
        await reader.setReportsDisplaying(false, in: kitchen)
        await reader.setReportsDisplaying(true, in: hangar)
        try await settle([host, reader], through: mailbox)

        for room in [kitchen, hangar] { try await host.send("anybody about", to: room) }
        try await settle([host, reader], through: mailbox)

        for room in [kitchen, hangar] {
            let theirs = try #require(reader.messages(in: room).first { !$0.isMine })
            await reader.markSeen(theirs.id, in: room)
        }
        try await settle([host, reader], through: mailbox)

        let quiet = try #require(host.messages(in: kitchen).first { $0.isMine })
        let loud = try #require(host.messages(in: hangar).first { $0.isMine })

        #expect(
            host.readBy(quiet.id, in: kitchen).first?.report == .doesNotReport,
            "a room told not to report sent a receipt anyway")
        #expect(
            host.readBy(loud.id, in: hangar).first?.report.wasDisplayed == true,
            "a room told to report did not")
    }

    @Test("The room's own answer survives a change to the usual one")
    func theRoomsAnswerSurvivesAChangeToTheUsualOne() async throws {
        let (_, reader, kitchen, hangar, _) = try await twoRooms()
        await reader.setReportsDisplaying(false, in: kitchen)

        await reader.setReportsDisplaying(true)

        #expect(
            !reader.isReportingDisplaying(in: kitchen),
            """
            Turning reporting on everywhere overrode a room that had been told never to report. \
            A per-room answer is the member's decision about that room and the global switch is \
            the default behind it, not a command.
            """)
        #expect(
            reader.isReportingDisplaying(in: hangar),
            "a room with no answer of its own did not follow the new usual answer")
    }

    @Test("A room can be put back to following the usual answer")
    func aRoomCanBePutBackToFollowing() async throws {
        let (_, reader, kitchen, _, _) = try await twoRooms()
        await reader.setReportsDisplaying(true)
        await reader.setReportsDisplaying(false, in: kitchen)
        #expect(!reader.isReportingDisplaying(in: kitchen))

        await reader.setReportsDisplaying(nil, in: kitchen)
        #expect(reader.reportsDisplayingAnswer(for: kitchen) == nil)
        #expect(
            reader.isReportingDisplaying(in: kitchen),
            "clearing a room's own answer did not return it to the usual one")
    }
}
