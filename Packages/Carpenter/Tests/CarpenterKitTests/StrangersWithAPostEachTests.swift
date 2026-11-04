@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Made-up people who each sign one post are still kept and passed on", .serialized)
struct StrangersWithAPostEachTests {
    private func writePacket(
        from sender: AppSession, to receiver: AppSession, through mailbox: InMemoryMailbox, carrying authors: [Author]
    ) async throws {
        var authors = authors
        var entries: [Entry] = []
        for index in authors.indices { entries.append(try authors[index].post("hi", at: TestSession.now)) }
        try await write(entries, from: sender, to: receiver, through: mailbox, carrying: authors)
    }

    private func write(
        _ entries: [Entry], from sender: AppSession, to receiver: AppSession, through mailbox: InMemoryMailbox,
        carrying authors: [Author]
    ) async throws {
        let receiverID = try #require(receiver.enrolment?.identity.id)
        let pairs = try #require(sender.pairs())
        let peer = try #require(sender.peers().first { $0.them == receiverID })
        let packet = try SyncEngine.pack(
            entries, for: [peer], certificates: authors.map(\.certificate),
            window: SyncSession.window(at: sender.clock.now), identities: authors.map(\.identity.publicKeys))
        try await mailbox.put(packet, to: receiverID, in: pairs)
    }

    @Test("Four packets of made-up people, one post each, add nobody to a member's phone and reach no contact")
    func strangersWithAPostAreNotKept() async throws {
        let t = try await RoomOfThree.make()
        let before = t.carol.replica.knownParticipants.count
        var made: [Author] = []
        for _ in 0..<4 {
            let batch = (0..<SyncSession.mostIdentitiesInAPacket).map { _ in Author(at: TestSession.now) }
            made += batch
            try await writePacket(from: t.sam, to: t.carol, through: t.mailbox, carrying: batch)
        }

        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        let added = t.carol.replica.knownParticipants.count - before

        #expect(added == 0, "one contact added \(added) made-up people to Carol's phone in one round")

        try await t.settle()
        let reachedAlice = made.filter { t.alice.replica.knownParticipants.contains($0.identity.id) }.count
        #expect(reachedAlice == 0, "Carol passed \(reachedAlice) made-up people on to Alice")
    }

    @Test("Made-up people writing into a member's own room are met a few a day from any one contact, not by the packet")
    func strangersInOurRoomAreMetAFewADay() async throws {
        let clock = TestClock(now: TestSession.now)
        let t = try await RoomOfThree.make(sharing: clock)
        let before = t.carol.replica.knownParticipants.count
        var batch = (0..<SyncSession.mostIdentitiesInAPacket).map { _ in Author(at: TestSession.now) }
        var entries: [Entry] = []
        for index in batch.indices {
            entries.append(try batch[index].append(.post("hi"), at: TestSession.now, room: t.room))
        }
        try await write(entries, from: t.sam, to: t.carol, through: t.mailbox, carrying: batch)

        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        let firstDay = t.carol.replica.knownParticipants.count - before
        #expect(
            firstDay == AppSession.mostNewcomersFromOnePersonADay,
            "one contact introduced \(firstDay) made-up people in a day")

        clock.advance(by: 86_400)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        let secondDay = t.carol.replica.knownParticipants.count - before - firstDay
        #expect(secondDay == AppSession.mostNewcomersFromOnePersonADay, "the next day met \(secondDay)")
    }

    @Test("Somebody a member's rooms name is met however many newcomers that contact has used")
    func somebodyTheRoomNamesIsMet() async throws {
        let t = try await RoomOfThree.make()
        let day = SyncSession.window(at: t.carol.clock.now)
        t.carol.persisted.newcomersFrom[t.samID] = DailyCount(day: day, count: AppSession.mostNewcomersFromOnePersonADay)
        let meeting = t.carol.whoToMeet(through: t.samID)

        #expect(meeting.newcomers == 0, "precondition: Sam has used the day's newcomers")
        #expect(meeting.known.isSuperset(of: [t.aliceID, t.samID]), "a member of Carol's room is not somebody she may meet")
        #expect(meeting.rooms.contains(t.room))
    }
}
