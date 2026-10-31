@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Watching what was refused")
struct RefusalWatchTests {
    private let now = Date(timeIntervalSince1970: 1_786_635_000)
    private let mallory = ParticipantID(rawValue: WideID.of([1]))
    private let bob = ParticipantID(rawValue: WideID.of([2]))

    private func refusal(from person: ParticipantID, packet: PacketID = PacketID(), isFinal: Bool = false) -> SyncReport.Refusal {
        SyncReport.Refusal(packet: packet, what: .entry, author: person, reason: "brokenLink", isFinal: isFinal, from: person)
    }

    private func replay(_ rounds: [(refusals: [SyncReport.Refusal], at: TimeInterval)]) -> [Bool] {
        var watch = RefusalWatch()
        return rounds.map { watch.holdsKeys(after: $0.refusals, at: now.addingTimeInterval($0.at)) }
    }

    @Test("Something refused for the first time holds keys, and the same thing refused again does not")
    func onlyWhatIsNewHolds() {
        let packet = refusal(from: mallory)
        let held = replay((0...10).map { ([packet], Double($0) * 5_000) })
        #expect(held == [true] + Array(repeating: false, count: 10))
    }

    @Test("Nothing refused holds nothing, and a final refusal is no reason to wait")
    func nothingHoldsNothing() {
        #expect(replay([([], 0), ([refusal(from: mallory, isFinal: true)], 1)]) == [false, false])
    }

    @Test("Somebody writing a new bad packet every round holds keys once an hour at most")
    func newPacketsAreRationed() {
        let minutes = (0...59).map { ([refusal(from: mallory)], Double($0) * 60) }
        let held = replay(minutes + [([refusal(from: mallory)], 3_600)])
        #expect(held == [true] + Array(repeating: false, count: 59) + [true])
    }

    @Test("One person's ration does not stop another person's refusal holding keys")
    func theRationIsPerPerson() {
        #expect(replay([([refusal(from: mallory)], 0), ([refusal(from: bob)], 1)]) == [true, true])
    }

    @Test("A refusal that stopped and came back is new, and still rationed")
    func aRefusalThatComesBackIsNew() {
        let packet = refusal(from: mallory)
        #expect(replay([([packet], 0), ([], 4_000), ([packet], 8_000)]) == [true, false, true])
        #expect(replay([([packet], 0), ([], 100), ([packet], 200)]) == [true, false, false])
    }
}

@MainActor
@Suite("A refused packet holds a room's keys for one round", .serialized)
struct ARefusedPacketHoldsKeysOnceTests {
    private struct Rig {
        let t: RoomOfThree
        let clock: TestClock
    }

    private func roomWithSomebodyOut() async throws -> Rig {
        let clock = TestClock(now: TestSession.now)
        let t = try await RoomOfThree.make(sharing: clock)
        try await t.alice.remove(t.samID, from: t.room)
        try await t.settle()
        try #require(t.carol.roster(of: t.room).absent.contains(t.samID), "precondition: Sam is out of the room")
        return Rig(t: t, clock: clock)
    }

    private func writeARefusedPacket(_ t: RoomOfThree) async throws {
        var forged = try DeviceCertificate.recovered(
            for: DeviceKeys.generate(), by: Identity.generate(), at: TestSession.now)
        forged.participant = t.aliceID
        let peer = try #require(t.sam.everyPeer().first { $0.them == t.carolID })
        let packet = try SyncEngine.pack(
            [], for: [peer], certificates: [forged], window: SyncSession.window(at: t.sam.clock.now))
        try await t.mailbox.put(packet, to: t.carolID, in: try #require(t.sam.pairs()))
    }

    private func owedAKey(_ t: RoomOfThree) throws -> Bool {
        t.carol.issuedGrants.removeAll()
        return try t.carol.grantsOwed().contains { $0.grant.room == t.room }
    }

    @Test("One packet left in place stops keys for the round it first appears and no longer")
    func onePacketHoldsOneRound() async throws {
        let rig = try await roomWithSomebodyOut()
        let t = rig.t
        try #require(try owedAKey(t), "precondition: Carol has a key to pass on")
        try await writeARefusedPacket(t)

        let first = try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        try #require(first.credentialsRejected == 1, "precondition: the packet was refused")
        #expect(!(try owedAKey(t)), "something new was refused and the keys were not held")

        for round in 2...10 {
            let later = try await t.carol.sync(through: t.mailbox, media: t.mailbox)
            try #require(later.credentialsRejected == 1, "precondition: the packet is refused again")
            #expect(try owedAKey(t), "the same packet held keys in round \(round)")
        }
    }

    @Test("The round that refuses something sends no key from a room with somebody out")
    func theHoldIsInTheRoundThatRefused() async throws {
        let rig = try await roomWithSomebodyOut()
        let t = rig.t
        t.carol.issuedGrants.removeAll()
        try await writeARefusedPacket(t)

        let first = try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        #expect(!first.written.flatMap(\.grants).contains { $0.room == t.room }, "a key went out in the round that refused")

        let second = try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        #expect(second.written.flatMap(\.grants).contains { $0.room == t.room }, "the key stayed held after the round")
    }

    @Test("A new bad packet every round does not stop a phone passing on keys")
    func aNewPacketEveryRoundDoesNotHoldForever() async throws {
        let rig = try await roomWithSomebodyOut()
        let t = rig.t
        var held = 0
        for _ in 0..<10 {
            rig.clock.advance(by: 60)
            try await writeARefusedPacket(t)
            try await t.carol.sync(through: t.mailbox, media: t.mailbox)
            if !(try owedAKey(t)) { held += 1 }
        }
        #expect(held == 1, "keys were held in \(held) rounds of ten")
    }

    @Test("A notification's look at the mailbox uses up nothing, so the next full round still waits")
    func aReadOnlyRoundDoesNotCount() async throws {
        let rig = try await roomWithSomebodyOut()
        let t = rig.t
        try await writeARefusedPacket(t)

        try await t.carol.sync(through: t.mailbox, media: t.mailbox, mode: .readOnly)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)

        #expect(!(try owedAKey(t)), "a read-only round used up the wait the full round owed")
    }

    @Test("A person joining a room somebody left gets their key while a bad packet sits there")
    func aNewMemberStillGetsTheKey() async throws {
        let rig = try await roomWithSomebodyOut()
        let t = rig.t
        try await writeARefusedPacket(t)
        for _ in 0..<3 { try await t.carol.sync(through: t.mailbox, media: t.mailbox) }

        let dave = TestSession.make(clock: rig.clock)
        await dave.load()
        try await dave.createIdentity(displayName: "Dave")
        try await join(dave, into: t.room, of: t.carol, through: t.mailbox)
        for _ in 0..<4 {
            for session in [t.alice, t.carol, dave] { try await session.sync(through: t.mailbox, media: t.mailbox) }
        }

        #expect(dave.chains[t.room] != nil, "a new member never got the room's key")
        #expect(dave.roster(of: t.room).members.contains(t.carolID))
    }
}
