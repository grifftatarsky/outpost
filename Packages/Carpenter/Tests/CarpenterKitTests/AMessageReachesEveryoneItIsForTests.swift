@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A message reaches everybody it is for", .serialized)
struct AMessageReachesEveryoneItIsForTests {
    private static let longMessage = String(repeating: "lantern ", count: 1_000)
        .trimmingCharacters(in: .whitespaces)

    @MainActor
    private struct Gathering {
        let mailbox: HookedMailbox
        let people: [String: AppSession]
        let rooms: [String: RoomID]

        subscript(_ name: String) -> AppSession { people[name]! }
        func id(_ name: String) -> ParticipantID { people[name]!.enrolment!.identity.id }
        func room(_ name: String) -> RoomID { rooms[name]! }

        func everybodySyncs(rounds: Int = 4, only: Set<String>? = nil) async throws {
            for _ in 0..<rounds {
                for name in people.keys.sorted() where only?.contains(name) ?? true {
                    try await people[name]!.sync(through: mailbox)
                }
            }
        }
    }

    private func gather(_ rooms: [(name: String, host: String, guests: [String])]) async throws -> Gathering {
        let mailbox = HookedMailbox()
        var people: [String: AppSession] = [:]
        let names = Set(rooms.flatMap { [$0.host] + $0.guests })
        for name in names.sorted() {
            let session = TestSession.make()
            await session.load()
            try await session.createIdentity(displayName: name)
            people[name] = session
        }
        var made: [String: RoomID] = [:]
        for room in rooms {
            let host = people[room.host]!
            let id = try await host.createRoom(named: room.name)
            made[room.name] = id
            for guest in room.guests {
                let joiner = people[guest]!
                let invite = try await host.invite(
                    joinerCode: await joiner.joinerCode(through: mailbox), joining: id, through: mailbox)
                try await joiner.redeem(inviteCode: try invite.encoded())
                for _ in 0..<5 {
                    try await host.sync(through: mailbox)
                    try await joiner.sync(through: mailbox)
                }
            }
        }
        let gathering = Gathering(mailbox: mailbox, people: people, rooms: made)
        try await gathering.everybodySyncs()
        for room in rooms {
            try #require(
                people[room.host]!.roster(of: made[room.name]!).members.count == room.guests.count + 1,
                "precondition: everybody is in \(room.name)")
        }
        return gathering
    }

    private func entries(to person: ParticipantID, in report: SyncReport) -> Set<EntryHash> {
        Set(report.written.filter { $0.to == person }.flatMap(\.entries))
    }

    @Test("A write that fails for one person goes to them next round, though somebody else's landed")
    func aFailedWriteIsStillOwedToThatPerson() async throws {
        let g = try await gather([("Kitchen", "Alice", ["Bob"]), ("Garden", "Alice", ["Carol"])])
        let (alice, bob, carol) = (g["Alice"], g["Bob"], g["Carol"])
        try await alice.send("for Carol", to: g.room("Garden"))
        let message = try #require(alice.messages(in: g.room("Garden")).last).id.entry

        await g.mailbox.cannotReach(g.id("Carol"))
        let first = try await alice.sync(through: g.mailbox)
        try #require(entries(to: g.id("Bob"), in: first).contains(message), "precondition: Bob's packet landed")
        try #require(!entries(to: g.id("Carol"), in: first).contains(message), "precondition: Carol's did not")

        _ = try await bob.sync(through: g.mailbox)
        _ = try? await alice.sync(through: g.mailbox)
        let mark = try #require(alice.messages(in: g.room("Garden")).last).delivery
        #expect(
            !mark.isCollected,
            "Bob collected his copy and the bubble said collected, while Carol, the one it was for, had nothing: \(mark)")

        await g.mailbox.reachesEveryone()
        let again = try await alice.sync(through: g.mailbox)
        #expect(
            entries(to: g.id("Carol"), in: again).contains(message),
            "the message counted as sent because Bob's packet landed, so Carol's was never written again")

        _ = try await carol.sync(through: g.mailbox)
        #expect(carol.messages(in: g.room("Garden")).contains { $0.body == "for Carol" })
    }

    @Test("A batch that fails after a removal went first is still owed, and so is the removed person's history")
    func aRemovalInTheFirstBatchDoesNotSkipTheRest() async throws {
        let g = try await gather([("Lanterns", "Alice", ["Carol", "Sam"])])
        let (alice, lanterns) = (g["Alice"], g.room("Lanterns"))
        for _ in 0..<120 { try await alice.send(Self.longMessage, to: lanterns) }
        try await alice.remove(g.id("Sam"), from: lanterns)
        let removal = try #require(alice.roster(of: lanterns).removal(of: g.id("Sam"))).entry
        let burst = Set(alice.messages(in: lanterns).filter { $0.body == Self.longMessage }.map(\.id.entry))

        await g.mailbox.inner.failWrite(number: 2, with: .unavailable)
        let first = try await alice.sync(through: g.mailbox)
        let firstToCarol = first.written.filter { $0.to == g.id("Carol") }
        try #require(firstToCarol.count == 1, "precondition: Carol's first packet landed and her second failed")
        try #require(firstToCarol[0].entries.contains(removal), "precondition: the removal went first")
        try #require(firstToCarol[0].entries.count < burst.count + 1, "precondition: the round needed two packets")

        let second = try await alice.sync(through: g.mailbox)
        let missing = burst.subtracting(firstToCarol[0].entries).subtracting(entries(to: g.id("Carol"), in: second))
        #expect(
            missing.isEmpty,
            "the removal's number moved the frontier past \(missing.count) messages in the batch that failed")

        let toSam = entries(to: g.id("Sam"), in: first).union(entries(to: g.id("Sam"), in: second))
        #expect(
            burst.isSubset(of: toSam),
            "Sam was skipped while his removal waited, and lost \(burst.subtracting(toSam).count) messages written before it")
    }

    @Test("A person skipped while their removal waits gets what was written elsewhere in that time")
    func aPersonWaitingToBeToldIsOwedTheOtherRooms() async throws {
        let g = try await gather([("Lanterns", "Alice", ["Bob", "Carol", "Sam"]), ("Garden", "Alice", ["Sam"])])
        let (alice, sam) = (g["Alice"], g["Sam"])
        await g.mailbox.cannotReach(g.id("Carol"))
        try await alice.remove(g.id("Sam"), from: g.room("Lanterns"))
        try await alice.send("while Sam waits", to: g.room("Garden"))
        let first = try await alice.sync(through: g.mailbox)
        try #require(alice.waitingToBeTold.contains(g.id("Sam")), "precondition: Sam is waiting to be told")
        try #require(first.written.contains { $0.to == g.id("Bob") }, "precondition: Bob's packet landed")

        await g.mailbox.reachesEveryone()
        try await g.everybodySyncs(only: ["Alice", "Carol", "Sam"])
        #expect(
            sam.messages(in: g.room("Garden")).contains { $0.body == "while Sam waits" },
            "Sam was left out of the round while his removal waited, and the frontier moved past what he was owed")
    }

    @Test("A change to this member's devices reaches a person whose write failed")
    func aChangeOfDevicesIsOwedPerPerson() async throws {
        let g = try await gather([("Kitchen", "Alice", ["Bob"]), ("Garden", "Alice", ["Carol"])])
        let alice = g["Alice"]
        alice.persisted.authorityAnnounced = Data(repeating: 0, count: 32)
        await g.mailbox.cannotReach(g.id("Carol"))
        let first = try await alice.sync(through: g.mailbox)
        try #require(first.written.contains { $0.to == g.id("Bob") }, "precondition: Bob was told")

        await g.mailbox.reachesEveryone()
        let ringsBefore = await g.mailbox.inner.rings.count { $0.to == g.id("Carol") }
        let second = try await alice.sync(through: g.mailbox)
        #expect(
            second.written.contains { $0.to == g.id("Carol") },
            "the change counted as told because Bob's packet landed, so Carol was never told")
        let ringsAfter = await g.mailbox.inner.rings.count { $0.to == g.id("Carol") }
        #expect(ringsAfter > ringsBefore, "Carol was written to and not rung")
    }
}
