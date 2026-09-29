@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A removed person hears last, and an answer they write after hearing lands after the removal everywhere", .serialized)
struct TellingTheRemovedLastTests {
    @Test("The remover writes nothing to the removed person until another member has read the removal or every space holds it")
    func theRemovedHearLast() async throws {
        let t = try await RoomOfThree.make()
        let alicesLine = HookedMailbox(inner: t.mailbox)
        await alicesLine.cannotReach(t.carolID)
        try await t.alice.remove(t.samID, from: t.room)
        _ = try? await t.alice.sync(through: alicesLine, media: t.mailbox)
        try await t.sam.sync(through: t.mailbox, media: t.mailbox)
        #expect(
            t.sam.roster(of: t.room).members.contains(t.samID),
            "Sam heard of his removal while Carol's space did not yet hold it")

        await alicesLine.reachesEveryone()
        try await t.alice.sync(through: alicesLine, media: t.mailbox)
        try await t.sam.sync(through: t.mailbox, media: t.mailbox)
        #expect(
            !t.sam.roster(of: t.room).members.contains(t.samID),
            "Sam was never told, although every other member's space held the removal")
    }

    @Test("A phone that holds somebody's removal sends them nothing written after it")
    func nothingMoreReachesTheRemoved() async throws {
        let t = try await RoomOfThree.make()
        try await t.alice.remove(t.samID, from: t.room)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        try #require(!t.carol.roster(of: t.room).members.contains(t.samID), "precondition: Carol has the removal")

        try await t.carol.send("after Sam", to: t.room)
        let said = try #require(t.carol.replica.allEntries.last { $0.author == t.carolID && $0.room == t.room })
        try await t.settle()
        #expect(t.sam.entriesByHash[said.hash] == nil, "Carol's phone sent Sam what she wrote after his removal")
    }

    @Test("A removal the removed person answers after hearing of it, claiming not to have seen it, stands on every phone")
    func anAnswerLandsAfterTheRemoval() async throws {
        let t = try await RoomOfThree.make()
        let seen = t.samSawBeforeTheRemoval()
        try await t.alice.remove(t.samID, from: t.room)
        try await t.settle()
        try #require(!t.sam.roster(of: t.room).members.contains(t.samID), "precondition: Sam has heard")

        let answer = try t.samAnswers(as: seen)
        _ = try t.sam.replica.integrate(answer)
        try await t.settle()

        try #require(t.carol.entriesByHash[answer.hash] != nil, "precondition: Carol holds Sam's answer")
        for (session, name) in [(t.alice, "Alice"), (t.carol, "Carol")] {
            let members = session.roster(of: t.room).members
            #expect(members.contains(t.aliceID), "Sam's answer put Alice out on \(name)'s phone")
            #expect(!members.contains(t.samID), "Sam's answer put him back in on \(name)'s phone")
        }
    }

    @Test("A member's second device takes the time the first could read a removal, and puts it ahead of the answer")
    func aSecondDeviceAgrees() async throws {
        let t = try await RoomOfThree.make()
        let relay = InMemoryEntrySync.Relay()
        t.carol.syncDevices(through: InMemoryEntrySync(relay: relay))
        let tablet = TestSession.make(keychain: await t.carolKeychain.sibling())
        tablet.syncDevices(through: InMemoryEntrySync(relay: relay))
        await tablet.load()
        try await t.carol.approveNewDevice(tablet)
        await tablet.settleDeviceSync { tablet.rooms.contains { $0.id == t.room } }

        let seen = t.samSawBeforeTheRemoval()
        try await t.alice.remove(t.samID, from: t.room)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        try await t.sam.sync(through: t.mailbox, media: t.mailbox)
        let answer = try t.samAnswers(as: seen)
        _ = try t.sam.replica.integrate(answer)
        try await t.sam.sync(through: t.mailbox, media: t.mailbox)
        try await tablet.sync(through: t.mailbox, media: t.mailbox)
        try #require(tablet.entriesByHash[answer.hash] != nil, "precondition: the tablet collected Sam's answer itself")

        for _ in 0..<4 {
            await t.carol.settleDeviceSync()
            await tablet.settleDeviceSync()
        }
        let members = tablet.roster(of: t.room).members
        #expect(members.contains(t.aliceID), "Carol's tablet put the answer ahead of a removal her phone read first")
        #expect(!members.contains(t.samID))
    }

    @Test("An answer written early to an address nobody looks at yet counts from when it could first be found")
    func anAnswerAddressedAheadCountsFromWhenItIsFound() async throws {
        let clock = TestClock(now: TestSession.now)
        let t = try await RoomOfThree.make(sharing: clock)
        let answer = try t.samAnswers(as: t.samSawBeforeTheRemoval())
        let ahead = SyncSession(mailbox: t.mailbox, pairs: try t.sam.currentPairs(), clock: clock)
        _ = try await ahead.send(
            [answer], to: t.sam.peers(), at: clock.now.addingTimeInterval(2 * SyncSession.tagWindow))

        clock.advance(by: 3600)
        try await t.alice.remove(t.samID, from: t.room)
        try await t.settle()
        try #require(t.carol.entriesByHash[answer.hash] == nil, "precondition: nobody could find the answer yet")

        clock.advance(by: SyncSession.tagWindow)
        try await t.settle()
        try #require(t.carol.entriesByHash[answer.hash] != nil, "precondition: a day on, Carol found the answer")
        let members = t.carol.roster(of: t.room).members
        #expect(
            members.contains(t.aliceID),
            """
            Sam wrote a removal of Alice before she removed him, to an address Carol would look at only the next \
            day. It was stored first, so it counted first, and Alice was out.
            """)
        #expect(!members.contains(t.samID))
    }

    @Test("An answer sealed under a key nobody held counts only from when the key arrived")
    func anAnswerUnderAHiddenKeyCountsFromTheKey() async throws {
        let t = try await RoomOfThree.make()
        let chain = try #require(t.sam.chains[t.room])
        let current = try #require(chain.highestKnownEpoch)
        let (madeUp, link) = try EpochChain.advance(from: try chain.secret(for: current), at: current, room: t.room)
        var hidden = chain
        hidden.adopt(madeUp, at: current.next)
        let answer = try t.samAnswers(as: t.samSawBeforeTheRemoval(), under: hidden, at: current.next)
        _ = try t.sam.replica.integrate(answer)
        try await t.sam.sync(through: t.mailbox, media: t.mailbox)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        try #require(t.carol.entriesByHash[answer.hash] != nil, "precondition: Carol holds the answer")

        try await t.alice.remove(t.samID, from: t.room)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        let grant = try EpochGrant.issue(
            madeUp, at: current.next, in: t.room, link: link,
            to: try #require(t.sam.pairwiseSecret(with: t.carolID)), devices: t.sam.deviceRecipients(of: t.carolID)
        ).signed(by: try #require(t.sam.enrolment?.device), from: t.samID, to: t.carolID)
        let secret = try #require(t.carol.pairwiseSecret(with: t.samID))
        try await t.carol.adopt(grant, from: Peer(secret: secret, them: t.samID, me: t.carolID), storedAt: .distantFuture)
        try #require(
            t.carol.chain(sealing: answer).flatMap(answer.opened(using:))?.type == .removal,
            "precondition: Carol can read the answer")

        try await t.settle()
        let members = t.carol.roster(of: t.room).members
        #expect(
            members.contains(t.aliceID),
            """
            Sam's removal of Alice reached Carol before Alice removed him, sealed under a key only he held, and \
            he handed her the key after. It counted from when it arrived, not from when she could read it.
            """)
        #expect(!members.contains(t.samID))
    }
}

@MainActor
@Suite("Another member's note decides a removal race, and lets the removed person be told", .serialized)
struct ASecondMembersNoteTests {
    @Test("The removed person is told once another member has read the removal, though a member cannot be reached")
    func toldOnceAnotherMemberHasReadIt() async throws {
        let t = try await RoomOfThree.make()
        let dave = try await t.bringInDave()
        let alicesLine = HookedMailbox(inner: t.mailbox)
        await alicesLine.cannotReach(try #require(dave.enrolment?.identity.id))

        try await t.alice.remove(t.samID, from: t.room)
        try await t.alice.sync(through: alicesLine, media: t.mailbox)
        try await t.sam.sync(through: t.mailbox, media: t.mailbox)
        try #require(
            t.sam.roster(of: t.room).members.contains(t.samID),
            "precondition: nobody else has read the removal and Dave's space does not hold it, so Sam is not told")

        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        try await t.alice.sync(through: alicesLine, media: t.mailbox)
        try await t.sam.sync(through: t.mailbox, media: t.mailbox)
        #expect(
            !t.sam.roster(of: t.room).members.contains(t.samID),
            "Carol had read the removal and noted it, and Sam was still waiting on a member nobody could reach")
    }

    @Test("A member whose copy of a removal came after the answer to it still counts the removal first, by another member's note")
    func aNoteOutranksALateCopy() async throws {
        let t = try await RoomOfThree.make()
        let dave = try await t.bringInDave()
        let daveID = try #require(dave.enrolment?.identity.id)
        let seen = t.samSawBeforeTheRemoval()
        let lines = (
            alice: HookedMailbox(inner: t.mailbox), carol: HookedMailbox(inner: t.mailbox),
            sam: HookedMailbox(inner: t.mailbox)
        )
        for line in [lines.alice, lines.carol, lines.sam] { await line.cannotReach(daveID) }

        try await t.alice.remove(t.samID, from: t.room)
        let removal = try #require(t.alice.roster(of: t.room).removal(of: t.samID)?.entry)
        try await t.alice.sync(through: lines.alice, media: t.mailbox)
        try await t.carol.sync(through: lines.carol, media: t.mailbox)
        try await t.alice.sync(through: lines.alice, media: t.mailbox)
        try await t.sam.sync(through: lines.sam, media: t.mailbox)
        try #require(!t.sam.roster(of: t.room).members.contains(t.samID), "precondition: Sam has been told")

        let answer = try t.samAnswers(as: seen)
        _ = try t.sam.replica.integrate(answer)
        await lines.sam.reachesEveryone()
        try await t.sam.sync(through: lines.sam, media: t.mailbox)
        try await dave.sync(through: t.mailbox, media: t.mailbox)
        try #require(dave.entriesByHash[answer.hash] != nil, "precondition: Dave has Sam's answer")
        try #require(dave.entriesByHash[removal] == nil, "precondition: Dave has no copy of the removal yet")

        let carolsNote = try #require(t.carol.replica.allEntries.first { entry in
            entry.author == t.carolID && t.carol.chain(sealing: entry).flatMap(entry.opened(using:))?.type == .removalNoted
        })
        for late in [try #require(t.alice.entriesByHash[removal]), carolsNote] { _ = try dave.replica.integrate(late) }
        let members = dave.roster(of: t.room).members
        #expect(
            members.contains(t.aliceID),
            """
            Dave's copy of Alice's removal reached him after Sam's answer, and he put the answer first, \
            although Carol had noted that her copy of the removal was stored before Sam could know of it.
            """)
        #expect(!members.contains(t.samID))
    }

    @Test("Two honest removals made at once end up decided the same way on all four phones")
    func anHonestRaceIsDecidedTheSameEverywhere() async throws {
        let t = try await RoomOfThree.make()
        let dave = try await t.bringInDave()
        try await t.alice.remove(t.samID, from: t.room)
        try await t.sam.remove(t.aliceID, from: t.room)
        for _ in 0..<6 {
            for session in [t.alice, t.carol, dave, t.sam] { try await session.sync(through: t.mailbox, media: t.mailbox) }
        }

        let rosters = [t.alice, t.carol, dave, t.sam].map { $0.roster(of: t.room).members }
        #expect(Set(rosters).count == 1, "the phones decided the race differently: \(rosters)")
        #expect(
            rosters.allSatisfy { $0.contains(t.aliceID) && !$0.contains(t.samID) },
            "Alice's removal reached the other members' spaces first, and Sam's stood somewhere")
    }
}

@Suite("When a phone could first read what it was sent")
struct WhenAPhoneCouldReadItTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    @Test("An entry from a device announced after the entry was stored counts from the announcement")
    func anUnannouncedDeviceCountsFromItsCertificate() throws {
        let identity = Identity.generate()
        let (phone, later) = (DeviceKeys.generate(), DeviceKeys.generate())
        var replica = Replica()
        replica.introduce(identity.publicKeys)
        let certificates = [
            try DeviceCertificate.recovered(for: phone, by: identity, at: start),
            try DeviceCertificate.issue(for: later, by: identity, at: start + 10, approvedBy: phone),
        ]
        let entry = try Entry.append(
            after: nil, author: identity.id, device: later, clock: VectorClock(), wallTime: start + 20, room: nil,
            payload: try Payload.post("from a device nobody had heard of"), at: .initial,
            sealedWith: EpochChain.create(room: RoomID()).chain)

        func packet(_ delivery: SyncEngine.Delivery, storedAt: Date) -> SyncSession.CollectedPackets.Opened {
            SyncSession.CollectedPackets.Opened(id: PacketID(), delivery: delivery, storedAt: storedAt, from: identity.id)
        }
        let collected = SyncSession.CollectedPackets(
            tags: [],
            packets: [
                packet(
                    SyncEngine.Delivery(entries: [], certificates: certificates, revocations: [], grants: []),
                    storedAt: start + 500),
                packet(
                    SyncEngine.Delivery(entries: [entry], certificates: [], revocations: [], grants: []),
                    storedAt: start + 30),
            ])
        let (report, _) = SyncSession.integrate(collected, into: &replica)
        try #require(report.integrated.contains { $0.hash == entry.hash }, "precondition: the entry was taken")
        #expect(
            report.readableFrom[entry.hash] == start + 500,
            "an entry signed by a device announced later counted from when its packet was stored")
    }

    @MainActor
    @Test("A packet found at an address this phone learned later counts from when it learned it")
    func anAddressLearnedLaterCountsFromThen() async throws {
        let t = try await RoomOfThree.make()
        try await t.alice.send("to be found", to: t.room)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        let peer = try #require(t.carol.peers().first { $0.them == t.aliceID })
        let session = SyncSession(mailbox: t.mailbox, pairs: try t.carol.currentPairs(), clock: t.carol.clock)
        let found = try await session.collect(as: peer, learned: [peer.secret: .distantFuture])
        try #require(!found.packets.isEmpty, "precondition: Carol found Alice's packet")
        #expect(found.packets.allSatisfy { $0.storedAt == .distantFuture })
    }
}

@MainActor
extension RoomOfThree {
    fileprivate struct Seen {
        let heads: [EntryHash]
        let clock: VectorClock
    }

    fileprivate func bringInDave() async throws -> AppSession {
        let dave = TestSession.make()
        await dave.load()
        try await dave.createIdentity(displayName: "Dave")
        try await join(dave, into: room, of: alice, through: mailbox)
        for _ in 0..<6 {
            for session in [alice, carol, sam, dave] { try await session.sync(through: mailbox, media: mailbox) }
        }
        let daveID = try #require(dave.enrolment?.identity.id)
        for session in [alice, carol, sam] {
            try #require(session.roster(of: room).members.contains(daveID), "precondition: everybody has Dave in the room")
        }
        return dave
    }

    fileprivate func samSawBeforeTheRemoval() -> Seen {
        Seen(heads: sam.lastEntries(of: aliceID, in: room), clock: sam.replica.frontier)
    }

    fileprivate func samAnswers(as seen: Seen, under chain: EpochChain? = nil, at epoch: EpochNumber? = nil) throws -> Entry {
        let enrolment = try #require(sam.enrolment)
        let held = chain ?? sam.chains[room]
        let sealing = try #require(held)
        let number = epoch ?? sealing.highestKnownEpoch
        return try Entry.append(
            after: sam.head, author: samID, device: enrolment.device, clock: seen.clock, wallTime: TestSession.now,
            room: room, payload: try Payload.removal(of: aliceID, heads: seen.heads), at: try #require(number),
            sealedWith: sealing, roomLink: RoomLink(previous: sam.roomHeads[room]?.hash))
    }
}
