@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("What a repair request says is held to a size", .timeLimit(.minutes(10)))
struct ARepairRequestIsBoundedTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    @Test("Authors, gaps and spans past the caps are dropped, and heads keep only the authors kept")
    func capsAreApplied() {
        let keptAuthor = ParticipantID(rawValue: WideID.of([1]))
        let authors = [keptAuthor] + (0..<(RepairRequest.mostAuthors + 5)).map { _ in
            ParticipantID(rawValue: WideID.of([UInt8.random(in: 2...255), UInt8.random(in: 0...255), UInt8.random(in: 0...255)]))
        }
        let feed = FeedKey(author: keptAuthor, device: DeviceID(rawValue: WideID.of([2])))
        let stranger = FeedKey(author: ParticipantID(rawValue: WideID.of([9, 9, 9, 9])), device: DeviceID(rawValue: WideID.of([3])))
        let manySpans = (0..<UInt64(RepairRequest.mostSpans + 10)).map { SequenceSpan($0 * 2 + 1, $0 * 2 + 1) }
        var heads = VectorClock()
        heads.observe(feed, seq: 4)
        heads.observe(stranger, seq: 9)
        let request = RepairRequest(
            authors: authors, heads: heads,
            gaps: [FeedGap(feed: feed, spans: manySpans)] + (0..<(RepairRequest.mostGaps + 5)).map { index in
                FeedGap(feed: feed, spans: [SequenceSpan(UInt64(index), UInt64(index))])
            })

        let bounded = request.bounded

        #expect(bounded.authors.count == RepairRequest.mostAuthors)
        #expect(bounded.gaps.flatMap(\.spans).count == RepairRequest.mostSpans)
        #expect(bounded.heads[feed] == 4)
        #expect(bounded.heads[stranger] == 0, "a head for somebody nobody asked about was kept")
    }

    @Test("Asking for one hole a thousand times is one walk and one copy")
    func overlappingGapsAreOneWalk() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)
        for index in 1...50 { try replica.integrate(try alice.post("\(index)", at: start)) }
        let gap = FeedGap(feed: alice.feedKey, spans: [SequenceSpan(1, 50)])

        let (served, unheld, _) = replica.fill(
            RepairRequest(authors: [], heads: VectorClock(), gaps: Array(repeating: gap, count: 1_000)))

        #expect(served.count == 50)
        #expect(unheld.isEmpty)
    }

    @Test("What an asker may not be handed is left out and named, never reported as not held")
    func withheldPositionsAreNamed() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)
        var entries: [Entry] = []
        for index in 1...4 {
            let entry = try alice.post("\(index)", at: start)
            entries.append(entry)
            try replica.integrate(entry)
        }
        let gap = FeedGap(feed: alice.feedKey, spans: [SequenceSpan(1, 6)])
        let secret = entries[1].hash

        let (served, unheld, elsewhere) = replica.fill(
            RepairRequest(authors: [alice.identity.id], heads: VectorClock(), gaps: [gap]),
            allowing: { $0.hash != secret })

        #expect(served.map(\.seq) == [1, 3, 4])
        #expect(elsewhere == [FeedGap(feed: alice.feedKey, spans: [SequenceSpan(2, 2)])])
        #expect(unheld == [FeedGap(feed: alice.feedKey, spans: [SequenceSpan(5, 6)])])
    }

    @Test("An answer that names nothing elsewhere has the bytes it always had, and an old answer still opens")
    func theAnswerOnTheWire() throws {
        let answer = RepairAnswer(request: RepairID(), unheld: [], heads: VectorClock())
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(answer)) as? [String: Any]
        #expect(Set(written?.keys.map { $0 } ?? []) == ["request", "unheld", "heads"])

        let old = try JSONDecoder().decode(RepairAnswer.self, from: JSONEncoder().encode(answer))
        #expect(old.elsewhere.isEmpty)
    }

    @Test("A request carried on past what was sent asks for what is left")
    func resumingMovesTheHeads() throws {
        var alice = Author()
        var entries: [Entry] = []
        for index in 1...6 { entries.append(try alice.post("\(index)", at: start)) }
        let request = RepairRequest(
            authors: [alice.identity.id], heads: VectorClock(),
            gaps: [FeedGap(feed: alice.feedKey, spans: [SequenceSpan(2, 5)])])

        let next = request.resumed(past: Array(entries.prefix(3)))

        #expect(next.id == request.id)
        #expect(next.heads[alice.feedKey] == 3)
        #expect(next.gaps == [FeedGap(feed: alice.feedKey, spans: [SequenceSpan(4, 5)])])
    }
}

@MainActor
@Suite("A request for history costs what the person asking is owed", .serialized, .timeLimit(.minutes(10)))
struct WhatARepairRequestCanCostTests {
    private func ask(
        _ requests: [RepairRequest], from sender: AppSession, to receiver: AppSession,
        through mailbox: InMemoryMailbox, certificates: [DeviceCertificate] = []
    ) async throws {
        let receiverID = try #require(receiver.enrolment?.identity.id)
        let peer = try #require(sender.peers().first { $0.them == receiverID })
        let packet = try SyncEngine.pack(
            [], for: [peer], certificates: certificates, window: SyncSession.window(at: sender.clock.now),
            requests: requests)
        try await mailbox.put(packet, to: receiverID, in: try #require(sender.pairs()))
    }

    private func wholeRoom(_ t: RoomOfThree, room: RoomID? = nil, reason: RepairReason = .gap) -> RepairRequest {
        RepairRequest(
            authors: [t.aliceID, t.carolID, t.samID], heads: VectorClock(), gaps: [], room: room ?? t.room, reason: reason)
    }

    private func delivered(to session: AppSession, from sender: AppSession, through mailbox: InMemoryMailbox) async throws -> [Entry] {
        try await waiting(for: session, from: sender, through: mailbox).entries
    }

    private func waiting(
        for session: AppSession, from sender: AppSession, through mailbox: InMemoryMailbox
    ) async throws -> SyncSession.CollectedPackets {
        let senderID = try #require(sender.enrolment?.identity.id)
        let reader = SyncSession(mailbox: mailbox, pairs: try #require(session.pairs()), clock: session.clock)
        return try await reader.collect(as: try #require(session.peers().first { $0.them == senderID }))
    }

    private func kitchen(_ t: RoomOfThree) async throws -> RoomID {
        let kitchen = try await t.alice.createRoom(named: "Kitchen")
        try await join(t.carol, into: kitchen, of: t.alice, through: t.mailbox)
        for index in 0..<4 { try await t.alice.send("kitchen \(index)", to: kitchen) }
        try await t.settle()
        return kitchen
    }

    @Test("Two thousand requests for one room are one duty and one answer")
    func oneDutyPerPersonPerRoom() async throws {
        let t = try await RoomOfThree.make()
        for index in 0..<10 { try await t.alice.send("history \(index)", to: t.room) }
        try await t.settle()

        try await ask((0..<2_000).map { _ in wholeRoom(t) }, from: t.sam, to: t.carol, through: t.mailbox)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)

        let answers = try await waiting(for: t.sam, from: t.carol, through: t.mailbox)
        #expect(!answers.packets.isEmpty, "precondition: the request was answered")
        #expect(answers.packets.count <= 2, "a request was answered more than once: \(answers.packets.count) packets")
        #expect(t.carol.persisted.repairDuties.isEmpty)
    }

    @Test("A later request replaces the one still waiting")
    func aNewRequestReplaces() async throws {
        let t = try await RoomOfThree.make()
        t.carol.takeRepairRequests([wholeRoom(t)], from: t.samID)
        let second = wholeRoom(t)
        t.carol.takeRepairRequests([second], from: t.samID)

        #expect(t.carol.persisted.repairDuties.map(\.request.id) == [second.id])
    }

    @Test("What a request says is cut to size before it is kept")
    func aDutyIsCutToSize() async throws {
        let t = try await RoomOfThree.make()
        let authors = [t.aliceID] + (0..<(RepairRequest.mostAuthors + 5)).map { _ in Identity.generate().id }

        t.carol.takeRepairRequests(
            [RepairRequest(authors: authors, heads: VectorClock(), gaps: [], room: t.room)], from: t.samID)

        #expect(t.carol.persisted.repairDuties.first?.request.authors.count == RepairRequest.mostAuthors)
    }

    @Test("Requests naming rooms the asker is not in leave nothing behind")
    func madeUpRoomsAreDropped() async throws {
        let t = try await RoomOfThree.make()
        let kitchen = try await kitchen(t)
        var requests = (0..<500).map { _ in wholeRoom(t, room: RoomID(rawValue: UUID())) }
        requests.append(wholeRoom(t, room: kitchen))
        requests.append(RepairRequest(authors: [t.aliceID], heads: VectorClock(), gaps: []))
        requests.append(RepairRequest(authors: [], heads: VectorClock(), gaps: [], wallOf: t.aliceID))

        t.carol.takeRepairRequests(requests, from: t.samID)

        #expect(t.carol.persisted.repairDuties.isEmpty)
    }

    @Test("An answer carries nothing from a room the asker is not in, whoever they name as authors")
    func answersStayInTheAskersRooms() async throws {
        let t = try await RoomOfThree.make()
        let kitchen = try await kitchen(t)
        try #require(t.carol.replica.allEntries.contains { $0.room == kitchen }, "precondition: Carol holds the Kitchen")

        try await ask([wholeRoom(t)], from: t.sam, to: t.carol, through: t.mailbox)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        let reached = try await delivered(to: t.sam, from: t.carol, through: t.mailbox)

        #expect(reached.contains { $0.room == t.room }, "precondition: the answer carried the room Sam is in")
        #expect(!reached.contains { $0.room == kitchen }, "Sam was handed a room he has never been in")
    }

    @Test("A named position in a room the asker is not in is named back, not sent")
    func aNamedPositionElsewhereIsNamedBack() async throws {
        let t = try await RoomOfThree.make()
        let kitchen = try await kitchen(t)
        let entry = try #require(t.carol.replica.allEntries.first { $0.room == kitchen })
        let gap = FeedGap(feed: entry.feedKey, spans: [SequenceSpan(entry.seq, entry.seq)])
        let filled = t.carol.replica.fill(
            RepairRequest(authors: [], heads: VectorClock(), gaps: [gap]), allowing: { $0.room == t.room })

        #expect(filled.entries.isEmpty)
        #expect(filled.elsewhere == [gap])
    }

    @Test("Spending a day's allowance stops the answer there, and it carries on the next day from where it stopped")
    func theBudgetCarriesOverToTheNextDay() async throws {
        let clock = TestClock(now: TestSession.now)
        let t = try await RoomOfThree.make(sharing: clock)
        for index in 0..<30 { try await t.alice.send("history \(index)", to: t.room) }
        try await t.settle()
        let day = SyncSession.window(at: clock.now)
        t.carol.persisted.repairSpend[t.samID] = RepairSpend(
            day: day, bytes: AppSession.repairBytesPerPersonPerDay - 4_000)

        try await ask([wholeRoom(t)], from: t.sam, to: t.carol, through: t.mailbox)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)

        let first = try await delivered(to: t.sam, from: t.carol, through: t.mailbox)
        #expect(!first.isEmpty, "nothing fitted the allowance left")
        #expect(t.carol.persisted.repairDuties.count == 1, "an answer cut short was marked finished")
        let duty = try #require(t.carol.persisted.repairDuties.first)
        #expect(!duty.request.heads.isEmpty, "the duty forgot how far it got")

        clock.advance(by: 86_400)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)

        let all = try await delivered(to: t.sam, from: t.carol, through: t.mailbox)
        let room = t.carol.replica.allEntries.filter { $0.room == t.room }
        #expect(Set(all.map(\.hash)).isSuperset(of: Set(room.map(\.hash))), "the rest did not go the next day")
        #expect(all.count == Set(all.map(\.hash)).count, "the second day sent what the first had")
        #expect(t.carol.persisted.repairDuties.isEmpty, "the duty did not finish")
    }

    @Test("A person past their allowance is sent nothing today, and the request waits")
    func nothingGoesPastTheBudget() async throws {
        let t = try await RoomOfThree.make()
        let day = SyncSession.window(at: t.carol.clock.now)
        t.carol.persisted.repairSpend[t.samID] = RepairSpend(day: day, bytes: AppSession.repairBytesPerPersonPerDay)

        try await ask([wholeRoom(t)], from: t.sam, to: t.carol, through: t.mailbox)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)

        let answers = try await waiting(for: t.sam, from: t.carol, through: t.mailbox)
        #expect(answers.packets.isEmpty, "a person past their allowance got an answer")
        #expect(t.carol.persisted.repairDuties.count == 1)
    }

    @Test("Every answer counts against the allowance, even an empty one")
    func anEmptyAnswerStillCosts() async throws {
        let t = try await RoomOfThree.make()
        let everybody: Set<ParticipantID> = [t.aliceID, t.carolID, t.samID]
        try await ask(
            [
                RepairRequest(
                    authors: Array(everybody), heads: t.carol.replica.heads(of: everybody), gaps: [], room: t.room)
            ], from: t.sam, to: t.carol, through: t.mailbox)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)

        #expect(t.carol.persisted.repairSpend[t.samID]?.bytes == AppSession.leastAnAnswerCosts)
    }

    @Test("A packet that keeps being refused does not get its request answered every round")
    func aRequestInARefusedPacketIsAnsweredOnce() async throws {
        let t = try await RoomOfThree.make()
        let stranger = Identity.generate()
        var forged = try DeviceCertificate.recovered(for: DeviceKeys.generate(), by: stranger, at: TestSession.now)
        forged.participant = t.aliceID

        try await ask([wholeRoom(t)], from: t.sam, to: t.carol, through: t.mailbox, certificates: [forged])
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        let first = try await waiting(for: t.sam, from: t.carol, through: t.mailbox).packets.count
        for _ in 0..<3 { try await t.carol.sync(through: t.mailbox, media: t.mailbox) }
        let later = try await waiting(for: t.sam, from: t.carol, through: t.mailbox).packets.count

        #expect(first > 0, "precondition: the request was answered")
        #expect(later == first, "the same request was answered again")
    }

    @Test("Nobody can push a held restore out of the list by asking a lot")
    func aHeldAskIsNotPushedOut() async throws {
        let t = try await RoomOfThree.make()
        let held = RestoreAskRecord(request: RepairID(), from: t.aliceID, room: t.room, at: TestSession.now, hold: .held)
        t.carol.persisted.restoreAsks = [held]
        for _ in 0..<(RestoreAskRecord.kept * 2) {
            t.carol.persisted.repairDuties = []
            t.carol.takeRepairRequests([wholeRoom(t, reason: .recovery)], from: t.samID)
            t.carol.persisted.restoreAsks.append(
                RestoreAskRecord(request: RepairID(), from: t.samID, room: nil, at: TestSession.now, hold: .allowed))
        }

        #expect(t.carol.persisted.restoreAsks.contains(held), "a request from somebody else released a hold")
    }

    @Test("A late joiner's holes from rooms they are not in close, and nothing from those rooms reaches them")
    func aLateJoinerEndsWithNoHoles() async throws {
        let clock = TestClock(now: TestSession.now)
        let t = try await RoomOfThree.make(sharing: clock)
        let kitchen = try await kitchen(t)
        for index in 0..<4 {
            try await t.alice.send("room \(index)", to: t.room)
            try await t.alice.send("elsewhere \(index)", to: kitchen)
        }
        try await t.settle()

        let dave = TestSession.make(clock: clock)
        await dave.load()
        try await dave.createIdentity(displayName: "Dave")
        try await join(dave, into: t.room, of: t.sam, through: t.mailbox)

        for wait: TimeInterval in [0, AppSession.holeSettlingDelay + 1, AppSession.automaticRepairInterval + 1] {
            clock.advance(by: wait)
            for _ in 0..<4 {
                for session in [t.alice, t.carol, t.sam, dave] {
                    try await session.sync(through: t.mailbox, media: t.mailbox)
                }
            }
        }

        #expect(dave.messages(in: t.room).contains { $0.body == "room 3" }, "the joiner did not get the room")
        #expect(!dave.replica.allEntries.contains { $0.room == kitchen }, "the joiner was handed a room they are not in")
        #expect(dave.missingHistory(in: t.room).isEmpty, "positions in a room they are not in stay missing for ever")
    }
}

@MainActor
@Suite("A hold follows the person, not the reason they give", .serialized, .timeLimit(.minutes(10)))
struct AHoldFollowsThePersonTests {
    private struct Restored {
        let peer: AppSession
        let fresh: AppSession
        let room: RoomID
        let mailbox: InMemoryMailbox
    }

    private func restored(holding: Bool = true) async throws -> Restored {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay()
        let original = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        let peer = TestSession.make(clock: clock)
        original.syncDevices(through: InMemoryEntrySync(relay: relay))
        for session in [original, peer] { await session.load() }
        try await original.createIdentity(displayName: "Griff")
        try await peer.createIdentity(displayName: "Outie")
        await peer.setHoldsHistoryForRestores(holding)
        let room = try await original.createRoom(named: "Kitchen")
        let invite = try await original.invite(
            joinerCode: await peer.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await peer.redeem(inviteCode: try invite.encoded())
        try await original.sync(through: mailbox)
        try await peer.accept(invite.attestation, from: try #require(original.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [original, peer] { try await session.sync(through: mailbox) }
        }
        try await original.send("said before", to: room)
        for _ in 0..<4 {
            for session in [original, peer] { try await session.sync(through: mailbox) }
        }
        await original.settleDeviceSync()
        let key = try #require(original.recoveryKeyText())

        clock.advance(by: 60)
        let fresh = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        fresh.syncDevices(through: InMemoryEntrySync(relay: relay))
        await fresh.load()
        try await fresh.restore(fromRecoveryKey: key)
        await fresh.setAsksPeersForHistory(false)
        await fresh.settleDeviceSync { !fresh.rooms.isEmpty }
        for _ in 0..<4 {
            for session in [fresh, peer] { try await session.sync(through: mailbox) }
        }
        return Restored(peer: peer, fresh: fresh, room: room, mailbox: mailbox)
    }

    private func crossed(_ t: Restored) async throws -> [Entry] {
        let peerID = try #require(t.peer.enrolment?.identity.id)
        let reader = SyncSession(mailbox: t.mailbox, pairs: try #require(t.fresh.pairs()), clock: t.fresh.clock)
        let collected = try await reader.collect(as: try #require(t.fresh.peers().first { $0.them == peerID }))
        let before = t.fresh.replica.allEntries.map(\.hash)
        return collected.entries.filter { !before.contains($0.hash) && $0.room == t.room }
    }

    private func ordinaryRepair(_ t: Restored) async throws {
        let peerID = try #require(t.peer.enrolment?.identity.id)
        let me = try #require(t.fresh.enrolment?.identity.id)
        let peer = try #require(t.fresh.peers().first { $0.them == peerID })
        let request = RepairRequest(
            authors: [me, peerID], heads: VectorClock(), gaps: [], room: t.room, reason: .gap)
        let packet = try SyncEngine.pack(
            [], for: [peer], certificates: try #require(t.fresh.replica.registry(for: me)).certificates,
            window: SyncSession.window(at: t.fresh.clock.now), requests: [request],
            identities: [try #require(t.fresh.enrolment?.identity.publicKeys)])
        try await t.mailbox.put(packet, to: peerID, in: try #require(t.fresh.pairs()))
    }

    @Test("A restored person calling their request ordinary is held like anybody else")
    func aGapFromARestoredPersonIsHeld() async throws {
        let t = try await restored()
        try await ordinaryRepair(t)

        try await t.peer.sync(through: t.mailbox)

        #expect(!t.peer.heldRestores().isEmpty, "a restored person walked around the hold by calling it an ordinary repair")
        #expect(!t.peer.persisted.repairDuties.isEmpty, "the request was dropped rather than held")
        try await t.peer.sync(through: t.mailbox)
        #expect(try await crossed(t).isEmpty, "history crossed while it was held")
    }

    @Test("Letting them through sends it, and an ordinary request after that goes straight through")
    func lettingThemThroughEndsTheHold() async throws {
        let t = try await restored()
        try await ordinaryRepair(t)
        try await t.peer.sync(through: t.mailbox)
        let me = try #require(t.fresh.enrolment?.identity.id)

        await t.peer.letHistoryThrough(to: me)
        try await t.peer.sync(through: t.mailbox)

        #expect(try await !crossed(t).isEmpty)
        #expect(t.peer.persisted.repairDuties.isEmpty)

        try await ordinaryRepair(t)
        try await t.peer.sync(through: t.mailbox)
        #expect(t.peer.heldRestores().isEmpty, "a person already let through was held again")
    }

    @Test("After saying no, an ordinary request from that person is refused too")
    func refusingCoversEveryReason() async throws {
        let t = try await restored()
        try await ordinaryRepair(t)
        try await t.peer.sync(through: t.mailbox)
        let me = try #require(t.fresh.enrolment?.identity.id)

        await t.peer.refuseHistory(to: me)
        try await ordinaryRepair(t)
        try await t.peer.sync(through: t.mailbox)

        #expect(try await crossed(t).isEmpty, "history crossed after the member said no")
        #expect(t.peer.persisted.repairDuties.isEmpty)
    }

    @Test("Somebody who chose not to hold is told, and the history goes")
    func withoutTheHoldItGoes() async throws {
        let t = try await restored(holding: false)
        try await ordinaryRepair(t)

        try await t.peer.sync(through: t.mailbox)

        #expect(t.peer.latestRestoreAsk() != nil, "a restored person asking was not noticed")
        #expect(try await !crossed(t).isEmpty)
    }

    @Test("A person who never restored is never held, whatever they ask for")
    func anOrdinaryMemberIsNotHeld() async throws {
        let t = try await RoomOfThree.make()
        t.carol.persisted.preferences.setHoldsHistoryForRestores(
            true, stamp: OrganisationStamp(at: TestSession.now, device: DeviceID(rawValue: WideID.of([1]))))
        t.carol.takeRepairRequests(
            [RepairRequest(authors: [t.samID], heads: VectorClock(), gaps: [], room: t.room)], from: t.samID)

        #expect(t.carol.heldRestores().isEmpty)
        #expect(t.carol.persisted.restoreAsks.isEmpty)
    }
}
