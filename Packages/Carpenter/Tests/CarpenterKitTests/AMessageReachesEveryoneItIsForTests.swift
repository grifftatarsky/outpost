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

    private func gather(
        _ rooms: [(name: String, host: String, guests: [String])]
    ) async throws -> (Gathering, [String: RoomID]) {
        var people: [String] = []
        for name in rooms.flatMap({ [$0.host] + $0.guests }) where !people.contains(name) { people.append(name) }
        let g = try await Gathering.of(people)
        var made: [String: RoomID] = [:]
        for room in rooms { made[room.name] = try await g.room(room.name, host: room.host, guests: room.guests) }
        return (g, made)
    }

    private func entries(to person: ParticipantID, in report: SyncReport) -> Set<EntryHash> {
        Set(report.written.filter { $0.to == person }.flatMap(\.entries))
    }

    @Test("A write that fails for one person goes to them next round, though somebody else's landed")
    func aFailedWriteIsStillOwedToThatPerson() async throws {
        let (g, rooms) = try await gather([("Kitchen", "Alice", ["Bob"]), ("Garden", "Alice", ["Carol"])])
        let (alice, bob, carol) = (g["Alice"], g["Bob"], g["Carol"])
        try await alice.send("for Carol", to: rooms["Garden"]!)
        let message = try #require(alice.messages(in: rooms["Garden"]!).last).id.entry

        await g.door("Alice").cannotReach(g.id("Carol"))
        let first = try await alice.sync(through: g.door("Alice"))
        try #require(entries(to: g.id("Bob"), in: first).contains(message), "precondition: Bob's packet landed")
        try #require(!entries(to: g.id("Carol"), in: first).contains(message), "precondition: Carol's did not")

        _ = try await bob.sync(through: g.door("Bob"))
        _ = try? await alice.sync(through: g.door("Alice"))
        let mark = try #require(alice.messages(in: rooms["Garden"]!).last).delivery
        #expect(
            !mark.isCollected,
            "Bob collected his copy and the bubble said collected, while Carol, the one it was for, had nothing: \(mark)")

        await g.door("Alice").reachesEveryone()
        let again = try await alice.sync(through: g.door("Alice"))
        #expect(
            entries(to: g.id("Carol"), in: again).contains(message),
            "the message counted as sent because Bob's packet landed, so Carol's was never written again")

        _ = try await carol.sync(through: g.door("Carol"))
        #expect(carol.messages(in: rooms["Garden"]!).contains { $0.body == "for Carol" })
    }

    @Test("A batch that fails after a removal went first is still owed, and so is the removed person's history")
    func aRemovalInTheFirstBatchDoesNotSkipTheRest() async throws {
        let (g, rooms) = try await gather([("Lanterns", "Alice", ["Carol", "Sam"])])
        let (alice, lanterns) = (g["Alice"], try #require(rooms["Lanterns"]))
        for _ in 0..<120 { try await alice.send(Self.longMessage, to: lanterns) }
        try await alice.remove(g.id("Sam"), from: lanterns)
        let removal = try #require(alice.roster(of: lanterns).removal(of: g.id("Sam"))).entry
        let burst = Set(alice.messages(in: lanterns).filter { $0.body == Self.longMessage }.map(\.id.entry))

        await g.cloud.failWrite(number: 2, with: .unavailable)
        let first = try await alice.sync(through: g.door("Alice"))
        let firstToCarol = first.written.filter { $0.to == g.id("Carol") }
        try #require(firstToCarol.count == 1, "precondition: Carol's first packet landed and her second failed")
        try #require(firstToCarol[0].entries.contains(removal), "precondition: the removal went first")
        try #require(firstToCarol[0].entries.count < burst.count + 1, "precondition: the round needed two packets")

        let second = try await alice.sync(through: g.door("Alice"))
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
        let (g, rooms) = try await gather([
            ("Lanterns", "Alice", ["Bob", "Carol", "Sam"]), ("Garden", "Alice", ["Sam"]),
        ])
        let (alice, sam) = (g["Alice"], g["Sam"])
        await g.door("Alice").cannotReach(g.id("Carol"))
        try await alice.remove(g.id("Sam"), from: rooms["Lanterns"]!)
        try await alice.send("while Sam waits", to: rooms["Garden"]!)
        let first = try await alice.sync(through: g.door("Alice"))
        try #require(alice.waitingToBeTold.contains(g.id("Sam")), "precondition: Sam is waiting to be told")
        try #require(first.written.contains { $0.to == g.id("Bob") }, "precondition: Bob's packet landed")

        await g.door("Alice").reachesEveryone()
        for _ in 0..<4 { await g.takeTurns("Alice", "Carol", "Sam") }
        #expect(
            sam.messages(in: rooms["Garden"]!).contains { $0.body == "while Sam waits" },
            "Sam was left out of the round while his removal waited, and the frontier moved past what he was owed")
    }

    @Test("A change to this member's devices reaches a person whose write failed")
    func aChangeOfDevicesIsOwedPerPerson() async throws {
        let (g, _) = try await gather([("Kitchen", "Alice", ["Bob"]), ("Garden", "Alice", ["Carol"])])
        let alice = g["Alice"]
        alice.persisted.authorityAnnounced = Data(repeating: 0, count: 32)
        await g.door("Alice").cannotReach(g.id("Carol"))
        let first = try await alice.sync(through: g.door("Alice"))
        try #require(first.written.contains { $0.to == g.id("Bob") }, "precondition: Bob was told")

        await g.door("Alice").reachesEveryone()
        let ringsBefore = await g.cloud.rings.count { $0.to == g.id("Carol") }
        let second = try await alice.sync(through: g.door("Alice"))
        #expect(
            second.written.contains { $0.to == g.id("Carol") },
            "the change counted as told because Bob's packet landed, so Carol was never told")
        let ringsAfter = await g.cloud.rings.count { $0.to == g.id("Carol") }
        #expect(ringsAfter > ringsBefore, "Carol was written to and not rung")
    }
}
