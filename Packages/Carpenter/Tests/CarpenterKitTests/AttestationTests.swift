import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@MainActor
@Suite("What one member tells another about somebody's log", .serialized)
struct AttestationTests {
    private func settle(_ sessions: [AppSession], _ mailbox: InMemoryMailbox, rounds: Int = 4) async throws {
        for _ in 0..<rounds {
            for session in sessions { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func three() async throws -> (
        alice: AppSession, bob: AppSession, carol: AppSession, room: ConversationID, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for session in [alice, bob, carol] { await session.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")
        let room = try await alice.createRoom(named: "Hangar 7")
        for joiner in [bob, carol] {
            let invite = try await alice.invite(joinerCode: joiner.identityCode(), joining: room, mailbox: nil)
            try await joiner.redeem(inviteCode: try invite.encoded())
        }
        try await settle([alice, bob, carol], mailbox, rounds: 6)
        return (alice, bob, carol, room, mailbox)
    }

    private func secondEntry(
        besides entry: Entry, by session: AppSession, saying words: String
    ) throws -> Entry {
        let enrolment = try #require(session.enrolment)
        let chain = try #require(session.chains[entry.conversation])
        let before = session.replica.entries(in: entry.feedKey, at: entry.seq - 1).first?.link
        return try Entry.append(
            after: before, author: enrolment.identity.id, device: enrolment.device,
            clock: VectorClock(), wallTime: entry.wallTime.addingTimeInterval(1),
            conversation: entry.conversation,
            payload: try Payload.post(words).sealed(
                at: entry.payload.epoch, using: chain, by: entry.feedKey))
    }

    @Test("Members who all tell the truth never contradict each other")
    func honestMembersAgree() async throws {
        let (alice, bob, carol, room, mailbox) = try await three()
        for (index, session) in [alice, bob, carol].enumerated() {
            try await session.send("line \(index)", to: room)
        }
        try await settle([alice, bob, carol], mailbox)

        let heard = [alice, bob, carol].map { $0.persisted.attestedHeads.count }.reduce(0, +)
        #expect(heard > 0, "no attestation crossed at all, so this test asserted nothing")
        for session in [alice, bob, carol] {
            #expect(session.persisted.contradictions.isEmpty)
            #expect(session.integrity.unexplainedContradictions == 0)
            #expect(session.replica.forks.isEmpty)
        }
    }

    @Test("A second entry at a position already passed along still reaches everybody, as a fork")
    func aForkForwardingWouldMissIsCaught() async throws {
        let (alice, bob, carol, room, mailbox) = try await three()
        try await alice.send("what everybody saw", to: room)
        try await settle([alice, bob, carol], mailbox)

        let aliceID = try #require(alice.enrolment?.identity.id)
        let seen = try #require(
            bob.replica.allEntries.filter { $0.author == aliceID && $0.conversation == room }
                .max { $0.seq < $1.seq })
        let other = try secondEntry(besides: seen, by: alice, saying: "what only Carol was shown")
        let outcome = try carol.replica.integrate(other)
        guard case .forked = outcome else {
            Issue.record("precondition: Carol should now hold two entries at one of Alice's positions")
            return
        }
        #expect(bob.replica.forks.isEmpty, "precondition: Bob knows nothing yet")

        try await settle([alice, bob, carol], mailbox)
        #expect(
            !bob.replica.allEntries.contains { $0.hash == other.hash },
            "precondition: forwarding alone carried the second entry, so this test proves nothing")

        try await carol.send("anyway", to: room)
        try await settle([alice, bob, carol], mailbox, rounds: 6)

        let recorded = bob.persisted.contradictions.map(\.contradiction)
        #expect(
            recorded.contains { $0.feed == seen.feedKey && $0.seq == seen.seq && $0.by == carol.enrolment?.identity.id },
            "Carol's attestation reached Bob and he noticed nothing")
        #expect(bob.integrity.unexplainedContradictions > 0)
        #expect(
            bob.replica.forks.contains { $0.feed == seen.feedKey && $0.seq == seen.seq },
            "Bob asked Carol for her copy and never ended up holding both")
    }

    @Test("A contradiction about somebody who just restored is kept, and not raised")
    func aRestoreExplainsIt() async throws {
        let (alice, bob, carol, room, mailbox) = try await three()
        try await alice.send("what everybody saw", to: room)
        try await settle([alice, bob, carol], mailbox)

        let aliceID = try #require(alice.enrolment?.identity.id)
        bob.persisted.restoreAsks.append(
            RestoreAskRecord(request: RepairID(), from: aliceID, room: room, at: TestSession.now, hold: .allowed))

        let seen = try #require(
            bob.replica.allEntries.filter { $0.author == aliceID && $0.conversation == room }
                .max { $0.seq < $1.seq })
        let other = try secondEntry(besides: seen, by: alice, saying: "after a restore")
        _ = try carol.replica.integrate(other)
        try await carol.send("anyway", to: room)
        try await settle([alice, bob, carol], mailbox, rounds: 6)

        #expect(!bob.persisted.contradictions.isEmpty, "the contradiction was not kept at all")
        #expect(bob.persisted.contradictions.allSatisfy { $0.explainedByRestore })
        #expect(bob.integrity.unexplainedContradictions == 0, "a restore was raised as though it were a lie")
    }

    @Test("Nobody is told about a log in a conversation they are not in")
    func attestationsStayInTheirConversation() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for session in [alice, bob, carol] { await session.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")
        let withBob = try await alice.createRoom(named: "Hangar 7")
        let withCarol = try await alice.createRoom(named: "Somewhere else")
        let toBob = try await alice.invite(joinerCode: bob.identityCode(), joining: withBob, mailbox: nil)
        try await bob.redeem(inviteCode: try toBob.encoded())
        let toCarol = try await alice.invite(joinerCode: carol.identityCode(), joining: withCarol, mailbox: nil)
        try await carol.redeem(inviteCode: try toCarol.encoded())
        try await settle([alice, bob, carol], mailbox, rounds: 6)

        try await carol.send("only in here", to: withCarol)
        try await alice.send("in here too", to: withCarol)
        try await alice.send("and in Bob's", to: withBob)
        try await settle([alice, bob, carol], mailbox)

        #expect(!bob.persisted.attestedHeads.isEmpty, "Bob heard no attestation, so this proves nothing")
        #expect(
            bob.persisted.attestedHeads.keys.allSatisfy { $0.conversation == withBob },
            "Bob was told about a log in a room he is not in")
        #expect(
            carol.persisted.attestedHeads.keys.allSatisfy { $0.conversation == withCarol },
            "Carol was told about a log in a room she is not in")
    }

    @Test("Somebody removed is never told how far the room went on without them")
    func aRemovedMemberLearnsNothingAfter() async throws {
        let (alice, bob, carol, room, mailbox) = try await three()
        try await alice.send("before", to: room)
        try await settle([alice, bob, carol], mailbox)

        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.remove(bobID, from: room)
        for index in 1...3 { try await alice.send("after \(index)", to: room) }
        try await settle([alice, bob, carol], mailbox)

        let aliceID = try #require(alice.enrolment?.identity.id)
        let feed = FeedKey(
            author: aliceID, device: try #require(alice.enrolment?.device.id), conversation: room)
        let removal = try #require(alice.roster(of: room).removal(of: bobID)?.entry)
        let removalSeq = try #require(alice.replica.entry(named: removal)?.seq)
        let aliceTop = alice.replica.allEntries.filter { $0.feedKey == feed }.map(\.seq).max() ?? 0
        #expect(aliceTop > removalSeq, "precondition: Alice wrote nothing after removing Bob")

        let removalEpoch = try #require(alice.replica.entry(named: removal)?.payload.epoch)
        let lastBobMayHave = alice.replica.allEntries
            .filter { $0.feedKey == feed && $0.payload.epoch <= removalEpoch }
            .map(\.seq).max() ?? 0
        let toldBob = bob.persisted.attestedHeads[feed]?.values.map(\.seq).max() ?? 0
        #expect(
            toldBob <= lastBobMayHave,
            "Bob was told Alice's log reached \(toldBob), past the last thing sealed before the key turned")
        #expect(
            !bob.replica.allEntries.contains { $0.feedKey == feed && $0.payload.epoch > removalEpoch },
            "Bob holds something sealed after the key turned on him")
        let after = alice.replica.allEntries.filter { $0.feedKey == feed && $0.payload.epoch > removalEpoch }
        #expect(!after.isEmpty, "precondition: nothing was sealed under the new key")
        for entry in after {
            #expect(bob.entryOpener()(entry) == nil, "Bob can read something said after he was removed")
        }
    }

    @Test("What was noticed is still there after a relaunch")
    func itSurvivesARelaunch() async throws {
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "attest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let bob = TestSession.make(keychain: keychain, at: directory)
        await bob.load()
        try await bob.createIdentity(displayName: "Bob")
        let feed = FeedKey(
            author: ParticipantID(rawValue: Data(repeating: 3, count: 32)),
            device: DeviceID(rawValue: Data(repeating: 4, count: 32)), conversation: .room(UUID()))
        bob.persisted.contradictions = [
            RecordedContradiction(
                contradiction: Contradiction(
                    feed: feed, seq: 5, held: EntryHash(rawValue: Data([1])),
                    attested: EntryHash(rawValue: Data([2])), by: feed.author),
                explainedByRestore: false)
        ]
        try await bob.saveState()

        let relaunched = TestSession.make(keychain: keychain, at: directory)
        await relaunched.load()
        #expect(relaunched.persisted.contradictions.count == 1)
        #expect(
            relaunched.integrity.unexplainedContradictions == 1,
            "a relaunch forgot what had been noticed, and the Integrity screen went quiet")
        #expect(!relaunched.integrity.isClean)
    }
}
