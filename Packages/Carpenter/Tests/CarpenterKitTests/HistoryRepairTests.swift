import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("What a replica can tell it is missing")
struct FeedGapTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    @Test("An interior hole is one span, and an entry from a peer closes it")
    func interiorHole() throws {
        var alice = Author()
        var replica = Replica()
        try replica.meet(alice)
        var entries: [Entry] = []
        for index in 1...5 { entries.append(try alice.post("\(index)", at: start)) }
        for entry in entries where entry.seq != 3 { try replica.integrate(entry) }

        #expect(replica.gaps() == [FeedGap(feed: alice.feedKey, spans: [SequenceSpan(3, 3)])])

        var full = Replica()
        try full.meet(alice)
        for entry in entries { try full.integrate(entry) }
        let request = RepairRequest(
            authors: [alice.identity.id], heads: replica.heads(of: [alice.identity.id]),
            gaps: replica.gaps())
        let (served, unheld) = full.fill(request)
        #expect(served.map(\.seq) == [3])
        #expect(unheld.isEmpty)

        for entry in served { try replica.integrate(entry) }
        #expect(replica.gaps().isEmpty)
    }

    @Test("A clock that names a later position makes the tail a hole")
    func tailNamedByAClock() throws {
        var alice = Author()
        var bob = Author()
        var replica = Replica()
        try replica.meet(alice)
        try replica.meet(bob)

        let one = try alice.post("one", at: start)
        _ = try alice.post("two", at: start)
        let three = try alice.post("three", at: start)
        try replica.integrate(one)
        try replica.integrate(try bob.post("reply", clock: three.clock, at: start))

        #expect(replica.gaps() == [FeedGap(feed: alice.feedKey, spans: [SequenceSpan(2, 3)])])
        #expect(replica.gaps(from: [bob.identity.id]).isEmpty)
    }

    @Test("A wall repair answers with what people wrote under the posts")
    func wallRepairIncludesTheThread() throws {
        var bob = Author()
        let wall = RoomID.outpost(of: bob.identity.id)
        var carol = Author(chain: bob.chain)

        var held = Replica()
        try held.meet(bob)
        try held.meet(carol)
        let post = try bob.append(Payload.post("the kite is up"), at: start)
        let comment = try carol.append(
            Payload.comment(on: post.hash, text: "it is holding well"), at: start, room: wall)
        try held.integrate(post)
        try held.integrate(comment)

        let (served, _) = held.fill(
            RepairRequest(
                authors: [], heads: VectorClock(), gaps: [], room: nil,
                wallOf: bob.identity.id))

        #expect(served.contains { $0.hash == post.hash }, "the post itself did not come back")
        #expect(
            served.contains { $0.hash == comment.hash },
            "a wall repair returned the posts and nothing anybody wrote under them")
    }

    @Test("A peer that lacks part of it says which, and sends what lies past the asker's head")
    func fillNamesWhatItLacks() throws {
        var alice = Author()
        var entries: [Entry] = []
        for index in 1...6 { entries.append(try alice.post("\(index)", at: start)) }

        var partial = Replica()
        try partial.meet(alice)
        for entry in entries where entry.seq != 2 { try partial.integrate(entry) }
        var asker = Replica()
        try asker.meet(alice)
        for entry in entries where entry.seq <= 3 && entry.seq != 2 { try asker.integrate(entry) }

        let request = RepairRequest(
            authors: [alice.identity.id], heads: asker.heads(of: [alice.identity.id]),
            gaps: asker.gaps())
        let (served, unheld) = partial.fill(request)
        #expect(served.map(\.seq) == [4, 5, 6])
        #expect(unheld == [FeedGap(feed: alice.feedKey, spans: [SequenceSpan(2, 2)])])
    }

    @Test("Nothing is asked of feeds from people the replica has never met")
    func strangersAreLeftOut() throws {
        var alice = Author()
        var stranger = Author()
        var replica = Replica()
        try replica.meet(alice)
        let theirs = try stranger.post("unseen", at: start)
        try replica.integrate(try alice.post("hello", clock: theirs.clock, at: start))
        #expect(replica.gaps().isEmpty)
    }
}

@Suite("A repair on the wire")
struct RepairWireTests {
    @Test("Requests and answers ride the sealed body, and a body without them still opens")
    func rideTheBody() throws {
        let a = Identity.generate()
        let b = Identity.generate()
        let mine = Peer(
            secret: try PairwiseSecret.derive(mine: a, theirs: b.publicKeys), them: b.id, me: a.id)
        let theirs = Peer(
            secret: try PairwiseSecret.derive(mine: b, theirs: a.publicKeys), them: a.id, me: b.id)
        let feed = FeedKey(author: a.id, device: DeviceID(rawValue: WideID.of([1])))
        var heads = VectorClock()
        heads[feed] = 3
        let request = RepairRequest(
            authors: [a.id], heads: heads, gaps: [FeedGap(feed: feed, spans: [SequenceSpan(2, 2)])])
        let answer = RepairAnswer(request: request.id, unheld: [], heads: heads)

        let packet = try SyncEngine.pack(
            [], for: [mine], window: 7, requests: [request], answers: [answer])
        let delivery = try SyncEngine.unpack(packet, as: theirs, window: 7)
        #expect(delivery.requests == [request])
        #expect(delivery.answers == [answer])

        let plain = try SyncEngine.pack([], for: [mine], window: 7)
        let opened = try SyncEngine.unpack(plain, as: theirs, window: 7)
        #expect(opened.requests.isEmpty && opened.answers.isEmpty)
    }
}

@MainActor
@Suite("Repairing a history with holes in it", .serialized)
struct HistoryRepairTests {
    private func joined() async throws -> (
        alice: AppSession, bob: AppSession, room: RoomID, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        return try await join(alice: alice, bob: bob, through: mailbox)
    }

    private func join(alice: AppSession, bob: AppSession, through mailbox: InMemoryMailbox)
        async throws -> (alice: AppSession, bob: AppSession, room: RoomID, mailbox: InMemoryMailbox)
    {
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        return (alice, bob, room, mailbox)
    }

    private func withAHole() async throws -> (
        alice: AppSession, bob: AppSession, room: RoomID, mailbox: InMemoryMailbox
    ) {
        let (alice, bob, room, mailbox) = try await joined()
        for word in ["first", "second", "third"] {
            try await alice.send(word, to: room)
            try await alice.sync(through: mailbox)
        }
        let written = await mailbox.writtenPackets.suffix(3)
        #expect(written.count == 3, "precondition: three packets were written")
        await mailbox.forget(packet: written[written.startIndex + 1])
        try await bob.sync(through: mailbox)
        return (alice, bob, room, mailbox)
    }

    @Test("A packet that vanished leaves a hole the reader can name, and the writer has none")
    func vanishedPacketIsAHole() async throws {
        let (alice, bob, room, _) = try await withAHole()
        let gaps = bob.missingHistory(in: room)
        #expect(gaps.total == 1, "one entry is missing: \(gaps)")
        #expect(gaps.first?.feed.author == alice.enrolment?.identity.id)
        #expect(alice.missingHistory(in: room).isEmpty)
        #expect(!bob.messages(in: room).contains { $0.body == "second" })
    }

    @Test("A withdrawn message and a hidden one are not holes")
    func softDeletesLeaveNoHole() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        try await alice.send("oops", to: room)
        try await alice.send("keep", to: room)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        let oops = try #require(alice.messages(in: room).first { $0.body == "oops" })
        try await alice.withdraw(oops.id)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        let keep = try #require(bob.messages(in: room).first { $0.body == "keep" })
        await bob.hide(keep.id)

        #expect(bob.missingHistory(in: room).isEmpty)
        #expect(alice.missingHistory(in: room).isEmpty)
    }

    @Test("A repair recovers the entry from the peer, says who was checked, and can be dismissed")
    func repairRecoversFromThePeer() async throws {
        let (alice, bob, room, mailbox) = try await withAHole()
        let aliceID = try #require(alice.enrolment?.identity.id)

        let started = try #require(await bob.startRepair(in: room))
        #expect(!started.isComplete)
        #expect(started.stillMissing == 1)
        #expect(started.asked.map(\.id) == [aliceID])

        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        let status = try #require(bob.repairStatus(of: room))
        #expect(status.isComplete)
        #expect(status.answered.map(\.id) == [aliceID])
        #expect(status.recovered == 1)
        #expect(status.stillMissing == 0)
        #expect(bob.messages(in: room).map(\.body).contains("second"))
        #expect(bob.missingHistory(in: room).isEmpty)

        let idle = try await alice.sync(through: mailbox)
        #expect(idle.entriesSent == 0, "the answer was treated as a fresh send")

        await bob.dismissRepair(in: room)
        #expect(bob.repairStatus(of: room) == nil)
    }

    @Test("A tail nobody re-sent cannot be named, and a repair still recovers it")
    func tailIsRecoveredThroughHeads() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        try await alice.send("last", to: room)
        try await alice.sync(through: mailbox)
        let last = try #require(await mailbox.writtenPackets.last)
        await mailbox.forget(packet: last)
        try await bob.sync(through: mailbox)
        #expect(bob.missingHistory(in: room).isEmpty, "no clock has mentioned it, so nothing can name it")
        #expect(!bob.messages(in: room).contains { $0.body == "last" })

        _ = await bob.startRepair(in: room)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        let status = try #require(bob.repairStatus(of: room))
        #expect(status.isComplete)
        #expect(status.stillMissing == 0)
        #expect(bob.messages(in: room).contains { $0.body == "last" })
    }

    @Test("A peer that lacks it says so, and the report counts what nobody asked can supply")
    func peerLackingItSaysSo() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        let (_, _, room, _) = try await join(alice: alice, bob: bob, through: mailbox)
        await carol.load()
        try await carol.createIdentity(displayName: "Carol")
        let invite = try await alice.invite(joinerCode: carol.identityCode(), joining: room, mailbox: nil)
        try await carol.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await carol.sync(through: mailbox)
        }
        for _ in 0..<3 {
            for member in [alice, bob, carol] { try await member.sync(through: mailbox) }
        }
        #expect(bob.roster(of: room).members.count == 3, "precondition: everybody is in")
        #expect(carol.roster(of: room).members.count == 3, "the late joiner was not handed the room")
        let carolID = try #require(carol.enrolment?.identity.id)

        for word in ["first", "second", "third"] {
            try await alice.send(word, to: room)
            try await alice.sync(through: mailbox)
        }
        let written = await mailbox.writtenPackets.suffix(3)
        await mailbox.forget(packet: written[written.startIndex + 1])
        try await bob.sync(through: mailbox)
        try await carol.sync(through: mailbox)
        #expect(bob.missingHistory(in: room).total == 1)
        #expect(carol.missingHistory(in: room).total == 1)

        _ = await bob.startRepair(in: room, asking: carolID)
        try await bob.sync(through: mailbox)
        try await carol.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        var status = try #require(bob.repairStatus(of: room))
        #expect(status.isComplete)
        #expect(status.answered.map(\.id) == [carolID])
        #expect(status.stillMissing == 1)
        #expect(status.heldByNobodyAsked == 1)
        #expect(status.sentButNotArrived == 0)

        _ = await bob.startRepair(in: room)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await carol.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        status = try #require(bob.repairStatus(of: room))
        #expect(status.isComplete)
        #expect(status.stillMissing == 0)
        #expect(status.recovered == 1)
        #expect(bob.messages(in: room).map(\.body).contains("second"))
    }

    @Test("A member who joins late is handed what came before, and learns who else is there")
    func lateJoinerIsHandedTheRoom() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        let (_, _, room, _) = try await join(alice: alice, bob: bob, through: mailbox)
        try await bob.send("before Carol", to: room)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        await carol.load()
        try await carol.createIdentity(displayName: "Carol")
        let invite = try await alice.invite(joinerCode: carol.identityCode(), joining: room, mailbox: nil)
        try await carol.redeem(inviteCode: try invite.encoded())
        try await carol.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await carol.sync(through: mailbox)
        try await carol.sync(through: mailbox)
        try await carol.sync(through: mailbox)

        #expect(carol.roster(of: room).members.count == 3)
        #expect(carol.messages(in: room).contains { $0.body == "before Carol" })
        #expect(carol.repairStatus(of: room) == nil, "the joiner's own question is not a banner")
    }

    @Test("A repair outlives a relaunch")
    func repairSurvivesRelaunch() async throws {
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "carpenter-repair-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let mailbox = InMemoryMailbox()
        let (_, bob, room, _) = try await join(
            alice: TestSession.make(), bob: TestSession.make(keychain: keychain, at: directory),
            through: mailbox)
        _ = await bob.startRepair(in: room)

        let again = TestSession.make(keychain: keychain, at: directory)
        await again.load()
        let status = try #require(again.repairStatus(of: room))
        #expect(!status.isComplete)
        #expect(status.asked.count == 1)
    }
}

@Suite("The gap index agrees with a scan")
struct GapIndexTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func byScan(_ held: Set<UInt64>, top: UInt64) -> [SequenceSpan] {
        guard top >= Entry.firstSequence else { return [] }
        return FeedGap.spans(of: (Entry.firstSequence...top).filter { !held.contains($0) })
    }

    @Test("However the entries arrive, the index names the same holes a scan would")
    func gapsAgreeWithAScanHoweverTheyArrive() throws {
        var alice = Author()
        var made: [Entry] = []
        for index in 1...12 { made.append(try alice.post("\(index)", at: start)) }

        let holes: Set<UInt64> = [3, 4, 9]
        let keeping = made.filter { !holes.contains($0.seq) }
        let held = Set(keeping.map(\.seq))

        for rotation in 0..<keeping.count {
            var replica = Replica()
            try replica.meet(alice)
            for entry in Array(keeping[rotation...] + keeping[..<rotation]) {
                try replica.integrate(entry)
            }
            let expected = byScan(held, top: held.max() ?? 0)
            let found = replica.gaps().first?.spans ?? []
            #expect(found == expected, "arrival rotation \(rotation) disagreed with a scan")
            #expect(replica.highestSequence(in: alice.feedKey) == held.max())
        }
    }

    @Test("A feed that arrives backwards ends with no holes")
    func backwardsArrivalClosesUp() throws {
        var alice = Author()
        var made: [Entry] = []
        for index in 1...8 { made.append(try alice.post("\(index)", at: start)) }

        var replica = Replica()
        try replica.meet(alice)
        for entry in made.reversed() { try replica.integrate(entry) }

        #expect(replica.gaps().isEmpty, "the contiguous run did not absorb what was waiting above it")
        #expect(replica.highestSequence(in: alice.feedKey) == 8)
    }

    @Test("A fork does not open a hole")
    func forkIsNotAHole() throws {
        var alice = Author()
        let one = try alice.post("one", at: start)
        var branch = alice
        let two = try alice.post("two", at: start)
        let rival = try branch.post("also two", at: start)
        #expect(two.seq == rival.seq && two.hash != rival.hash, "precondition: this is a fork")

        var replica = Replica()
        try replica.meet(alice)
        try replica.integrate(one)
        try replica.integrate(two)
        guard case .forked = try replica.integrate(rival) else {
            Issue.record("the rival entry did not read as a fork")
            return
        }

        #expect(replica.gaps().isEmpty, "a fork was counted as a hole")
        #expect(replica.highestSequence(in: alice.feedKey) == 2)
    }
}

@Suite("A refusal that no credential can lift")
struct FinalRefusalTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    @Test("An entry signed after its device was revoked is refused for good")
    func afterRevocationIsFinal() throws {
        var alice = Author(at: start)
        var replica = Replica()
        try replica.meet(alice)

        let before = try alice.post("while allowed", at: start)
        try replica.integrate(before)

        let revokedAt = start.addingTimeInterval(60)
        try replica.revoke(
            DeviceRevocation.issue(for: alice.device.id, by: alice.identity, at: revokedAt))

        let after = try alice.post("after the revocation", at: revokedAt.addingTimeInterval(1))
        #expect(throws: LogError.unauthorizedDevice) { try replica.integrate(after) }
        #expect(replica.refusesForever(after), "the refusal was treated as a credential in flight")

        var stranger = Author(at: start)
        let theirs = try stranger.post("hello", at: start)
        #expect(!replica.refusesForever(theirs))
    }

    @Test("A device this replica has never been shown is not a final refusal")
    func unknownDeviceIsNotFinal() throws {
        var alice = Author(at: start)
        var replica = Replica()
        replica.introduce(alice.identity.publicKeys)

        let entry = try alice.post("no certificate yet", at: start)
        #expect(throws: LogError.unauthorizedDevice) { try replica.integrate(entry) }
        #expect(!replica.refusesForever(entry))
    }

    @Test("A packet whose only refusal is final still settles")
    func finalRefusalDoesNotHoldThePacket() throws {
        var alice = Author(at: start)
        let a = Identity.generate()
        let b = Identity.generate()
        let mine = Peer(
            secret: try PairwiseSecret.derive(mine: a, theirs: b.publicKeys), them: b.id, me: a.id)
        let theirs = Peer(
            secret: try PairwiseSecret.derive(mine: b, theirs: a.publicKeys), them: a.id, me: b.id)

        var replica = Replica()
        try replica.meet(alice)
        let revokedAt = start.addingTimeInterval(60)
        try replica.revoke(
            DeviceRevocation.issue(for: alice.device.id, by: alice.identity, at: revokedAt))
        let rogue = try alice.post("after the revocation", at: revokedAt.addingTimeInterval(1))

        let packet = try SyncEngine.pack([rogue], for: [mine], window: 7)
        let collected = SyncSession.CollectedPackets(
            tags: [theirs.incomingTag(window: 7)],
            packets: [
                .init(id: packet.id, delivery: try SyncEngine.unpack(packet, as: theirs, window: 7))
            ])
        let (report, settled) = SyncSession.integrate(collected, into: &replica)

        #expect(report.entriesRefusedForever == 1)
        #expect(report.entriesRejected == 0, "a final refusal was counted as one that may pass")
        #expect(settled.contains(packet.id), "the packet would be fetched and refused every round")
        #expect(report.refusals.first?.isFinal == true)
        #expect(report.refusals.first?.seq == rogue.seq)
        #expect(report.refusals.first?.feed == rogue.feedKey)
    }

    @Test("A recorded position is left out of what is still missing")
    func recordedPositionsAreLeftOut() {
        let feed = FeedKey(
            author: ParticipantID(rawValue: Data(repeating: 5, count: 32)),
            device: DeviceID(rawValue: WideID.of([1])))
        var refused: [FeedGap] = []
        refused.insert(feed, 4)
        refused.insert(feed, 5)
        refused.insert(feed, 4)
        #expect(refused == [FeedGap(feed: feed, spans: [SequenceSpan(4, 5)])])

        let missing = [FeedGap(feed: feed, spans: [SequenceSpan(2, 6)])]
        #expect(
            missing.subtracting(refused)
                == [FeedGap(feed: feed, spans: [SequenceSpan(2, 3), SequenceSpan(6, 6)])])
        #expect(missing.subtracting([]) == missing)
        #expect(refused.stillMissing(of: missing) == 2)
    }
}

@MainActor
@Suite("Repairing without being asked", .serialized)
struct AutomaticRepairTests {
    private func joined(_ clock: TestClock) async throws -> (
        alice: AppSession, bob: AppSession, room: RoomID, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = AppSession(storage: TestSession.storage(), clock: clock)
        let bob = AppSession(storage: TestSession.storage(), clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        return (alice, bob, room, mailbox)
    }

    private func withAHole(_ clock: TestClock) async throws -> (
        alice: AppSession, bob: AppSession, room: RoomID, mailbox: InMemoryMailbox
    ) {
        let (alice, bob, room, mailbox) = try await joined(clock)
        for word in ["first", "second", "third"] {
            try await alice.send(word, to: room)
            try await alice.sync(through: mailbox)
        }
        let written = await mailbox.writtenPackets.suffix(3)
        await mailbox.forget(packet: written[written.startIndex + 1])
        try await bob.sync(through: mailbox)
        return (alice, bob, room, mailbox)
    }

    @Test("A hole that sits there is chased on its own, and recovered")
    func chasedWithoutBeingAsked() async throws {
        let clock = TestClock(now: TestSession.now)
        let (alice, bob, room, mailbox) = try await withAHole(clock)
        #expect(bob.missingHistory(in: room).total == 1)

        try await bob.sync(through: mailbox)
        #expect(bob.repairStatus(of: room) == nil, "an automatic repair is not drawn")
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        #expect(!bob.messages(in: room).map(\.body).contains("second"), "it was chased too early")

        clock.advance(by: AppSession.holeSettlingDelay + 1)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        #expect(bob.messages(in: room).map(\.body).contains("second"))
        #expect(bob.missingHistory(in: room).isEmpty)
        #expect(bob.repairStatus(of: room) == nil, "the app's own repair left a banner behind")
    }

    @Test("A room is asked about at most once an hour, however many holes appear")
    func rateLimited() async throws {
        let clock = TestClock(now: TestSession.now)
        let (alice, bob, room, mailbox) = try await withAHole(clock)

        clock.advance(by: AppSession.holeSettlingDelay + 1)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        #expect(bob.missingHistory(in: room).isEmpty, "precondition: the first hole was filled")

        for word in ["fourth", "fifth", "sixth"] {
            try await alice.send(word, to: room)
            try await alice.sync(through: mailbox)
        }
        let written = await mailbox.writtenPackets.suffix(3)
        await mailbox.forget(packet: written[written.startIndex + 1])
        try await bob.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        #expect(bob.missingHistory(in: room).total == 1, "precondition: a second hole")
        let settled = await mailbox.writeCount

        clock.advance(by: AppSession.holeSettlingDelay + 1)
        for _ in 0..<5 {
            clock.advance(by: 60)
            try await bob.sync(through: mailbox)
        }
        #expect(
            await mailbox.writeCount == settled,
            "the room was asked again within the hour of the last time")

        clock.advance(by: AppSession.automaticRepairInterval)
        try await bob.sync(through: mailbox)
        #expect(await mailbox.writeCount > settled, "the room was never asked again")
    }

    @Test("A request nobody has answered is not sent twice")
    func oneRequestAtATime() async throws {
        let clock = TestClock(now: TestSession.now)
        let (_, bob, room, mailbox) = try await withAHole(clock)
        #expect(bob.missingHistory(in: room).total == 1, "precondition: there is a hole to ask about")

        try await bob.sync(through: mailbox)
        let quiet = await mailbox.writeCount
        try await bob.sync(through: mailbox)
        #expect(await mailbox.writeCount == quiet, "precondition: an idle round writes nothing")

        clock.advance(by: AppSession.holeSettlingDelay + 1)
        try await bob.sync(through: mailbox)
        let afterAsking = await mailbox.writeCount
        #expect(afterAsking > quiet, "precondition: a request actually went out")

        for _ in 0..<4 {
            clock.advance(by: AppSession.automaticRepairInterval + 1)
            try await bob.sync(through: mailbox)
        }
        #expect(
            await mailbox.writeCount == afterAsking,
            "a second request was written while the first was still waiting")
    }

    @Test("A hole that appears after the question is asked about anyway")
    func aLaterHoleIsStillAskedAbout() async throws {
        let clock = TestClock(now: TestSession.now)
        let (alice, bob, room, mailbox) = try await withAHole(clock)

        clock.advance(by: AppSession.holeSettlingDelay + 1)
        try await bob.sync(through: mailbox)
        #expect(bob.repairStatus(of: room) == nil, "the app's own question is drawn nowhere")

        let beforeAnswer = Set(await mailbox.writtenPackets)
        try await alice.sync(through: mailbox)
        for packet in await mailbox.writtenPackets where !beforeAnswer.contains(packet) {
            await mailbox.forget(packet: packet)
        }
        try await bob.sync(through: mailbox)
        #expect(bob.missingHistory(in: room).total == 1, "precondition: the first hole is still open")

        for word in ["fourth", "fifth", "sixth"] {
            try await alice.send(word, to: room)
            try await alice.sync(through: mailbox)
        }
        let written = await mailbox.writtenPackets.suffix(3)
        await mailbox.forget(packet: written[written.startIndex + 1])
        try await bob.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        #expect(bob.missingHistory(in: room).total == 2, "precondition: two holes, one never asked about")

        let quiet = await mailbox.writeCount
        try await bob.sync(through: mailbox)
        #expect(await mailbox.writeCount == quiet, "precondition: an idle round writes nothing")

        clock.advance(by: AppSession.automaticRepairInterval + AppSession.holeSettlingDelay + 2)
        try await bob.sync(through: mailbox)
        #expect(
            await mailbox.writeCount > quiet,
            "a hole nobody had been asked about was never asked about")
    }

    @Test("A repair the member started is not replaced by the app's own")
    func doesNotReplaceTheMembersOwn() async throws {
        let clock = TestClock(now: TestSession.now)
        let (alice, bob, room, mailbox) = try await withAHole(clock)

        let other = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: other, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        for word in ["one", "two", "three"] {
            try await alice.send(word, to: other)
            try await alice.sync(through: mailbox)
        }
        let written = await mailbox.writtenPackets.suffix(3)
        await mailbox.forget(packet: written[written.startIndex + 1])
        try await bob.sync(through: mailbox)
        #expect(bob.missingHistory(in: other).total == 1, "precondition: the other room has a hole")

        let started = try #require(await bob.startRepair(in: room))
        try await bob.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        let quiet = await mailbox.writeCount
        try await bob.sync(through: mailbox)
        #expect(await mailbox.writeCount == quiet, "precondition: an idle round writes nothing")

        clock.advance(by: AppSession.holeSettlingDelay + 1)
        try await bob.sync(through: mailbox)

        #expect(
            await mailbox.writeCount > quiet,
            "precondition: the app asked about the other room in this round")
        #expect(bob.repairStatus(of: room)?.id == started.id, "the member's own repair was replaced")
    }
}

@MainActor
@Suite("A refusal a member is told about", .serialized)
struct FinalRefusalThroughTheSessionTests {
    private func settle(_ session: AppSession, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return }
            await session.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    @Test("An entry a revoked device signed is counted apart, and never asked for again")
    func aFinalRefusalIsRecordedAndSaidApart() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let keychain = InMemoryKeychainStore()
        let relay = InMemoryEntrySync.Relay()

        func session(sharing keychain: any KeychainStore = InMemoryKeychainStore()) -> AppSession {
            AppSession(storage: TestSession.storage(keychain: keychain), clock: clock)
        }

        let phone = session(sharing: keychain)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        await phone.load()
        try await phone.createIdentity(displayName: "Alice")
        let room = try await phone.createRoom(named: "Lanterns")

        try await keychain.remove(IdentityStore.deviceKey)
        let pad = session(sharing: keychain)
        pad.syncDevices(through: InMemoryEntrySync(relay: relay))
        await pad.load()
        await settle(pad) { pad.rooms.contains { $0.id == room } }
        #expect(pad.rooms.contains { $0.id == room }, "precondition: the pad has the room")

        let bob = session()
        let carol = session()
        for one in [bob, carol] { await one.load() }
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")

        for joiner in [bob, carol] {
            let invite = try await phone.invite(
                joinerCode: joiner.identityCode(), joining: room, mailbox: nil)
            try await joiner.redeem(inviteCode: try invite.encoded())
            try await phone.sync(through: mailbox)
            try await joiner.accept(
                invite.attestation, from: try #require(phone.enrolment?.identity.publicKeys))
        }

        try await pad.send("from the pad, while allowed", to: room)
        for _ in 0..<8 {
            for one in [phone, pad, bob, carol] { try await one.sync(through: mailbox) }
        }
        #expect(
            bob.messages(in: room).map(\.body).contains("from the pad, while allowed"),
            "precondition: Bob holds the pad's earlier work")

        let padDevice = try #require(pad.enrolment?.device.id)
        try await phone.revoke(padDevice)

        clock.advance(by: 60)
        let beforePad = Set(await mailbox.writtenPackets)
        try await pad.send("after the pad was revoked", to: room)
        try await pad.sync(through: mailbox)

        try await carol.sync(through: mailbox)
        try await carol.sync(through: mailbox)
        #expect(
            carol.messages(in: room).map(\.body).contains("after the pad was revoked"),
            "precondition: Carol accepted it")

        for packet in await mailbox.writtenPackets where !beforePad.contains(packet) {
            await mailbox.forget(packet: packet)
        }

        try await phone.sync(through: mailbox)
        for _ in 0..<3 { try await bob.sync(through: mailbox) }

        try await carol.send("and this, from Carol", to: room)
        try await carol.sync(through: mailbox)
        for _ in 0..<3 { try await bob.sync(through: mailbox) }

        #expect(
            bob.messages(in: room).map(\.body).contains("and this, from Carol"),
            "precondition: Bob has Carol's message and the claim it carries")
        #expect(
            !bob.messages(in: room).map(\.body).contains("after the pad was revoked"),
            "precondition: the refused entry did not reach Bob by an ordinary route")
        #expect(bob.missingHistory(in: room).total == 1, "precondition: Bob can tell one is missing")

        try await bob.startRepair(in: room)
        try await bob.sync(through: mailbox)
        try await carol.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        let status = try #require(bob.repairStatus(of: room))
        #expect(status.unverifiable == 1, "the refusal was not recorded, or not counted apart")
        #expect(
            status.sentButNotArrived == 0,
            "an entry that will never be accepted was drawn as one still on its way")
        #expect(
            bob.missingHistory(in: room).isEmpty,
            "the room still reports missing something no credential will ever make readable")

        await bob.dismissRepair(in: room)
        let again = await bob.startRepair(in: room)
        #expect(again?.stillMissing == 0, "a fresh repair asked for it all over again")
    }
}
