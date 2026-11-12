@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("The order things arrive in", .serialized, .timeLimit(.minutes(10)), .tags(.sync, .manyDevices))
struct TheOrderThingsArriveInTests {
    private static let longMessage = String(repeating: "lantern ", count: 1_000)
        .trimmingCharacters(in: .whitespaces)

    @Test(
        "A message sent within two seconds of a round still waits for a removal stored in between",
        arguments: [false, true])
    func aSendSoonAfterARoundStillSeesTheRemoval(viewIsHeld: Bool) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol"])

        await g.takeTurns("Bob")
        if viewIsHeld { await g.door("Bob").holdView() }
        try await g["Alice"].remove(g.id("Bob"), from: room)
        await g.takeTurns("Alice")
        try? await g["Bob"].send("after my removal", to: room, after: g.door("Bob"))

        #expect(!g.shows("after my removal", in: room, on: "Bob"), "Bob wrote into a room he had been removed from")
        #expect(g["Bob"].roster(of: room).removal(of: g.id("Bob")) != nil, "Bob was not told he was removed")
    }

    @Test(
        "A burst stored in one instant comes back with nothing missing, and a wish changed twice ends as the later one",
        arguments: 0..<8)
    func aBurstFromOneInstantLosesNothing(seed: Int) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])
        await g.cloud.sameInstant(within: 1, seed: UInt64(seed))

        g.away("Erin")
        for _ in 0..<30 { try await g["Alice"].send(Self.longMessage, to: room) }
        await g.takeTurns("Alice")
        await g["Alice"].setNotified(true, about: g.id("Erin"))
        await g.takeTurns("Alice")
        await g["Alice"].setNotified(false, about: g.id("Erin"))
        await g.takeTurns("Alice")
        let sent = await g.cloud.everySentPacket
        let packetsForErin = await g.cloud.writtenPackets.filter { sent[$0]?.to == g.id("Erin") }
        try #require(packetsForErin.count > 2, "precondition: several packets wait for Erin, stored in one instant")

        g.back("Erin")
        await g.door("Erin").skip(packetsForErin[1])
        try await g.settle()
        #expect(await g.door("Erin").faultsPending == 0, "Erin never left out the packet she was told to skip")
        g.advance(by: AppSession.holeSettlingDelay + 1)
        try await g.settle()

        g.sameRoom(room, on: ["Alice", "Erin"])
        #expect(g["Erin"].missingHistory(in: room).isEmpty, "Erin is missing history after a burst")
        #expect(g["Erin"].persisted.askedAutomatically[room] == nil, "Erin started a repair for a burst")
        let earlierWishStands = g["Erin"].wantsOutpostBellFrom(g.id("Alice"))
        withKnownIssue("a wish turned off a round after it was turned on stands on some runs", isIntermittent: true) {
            #expect(!earlierWishStands, "Alice's earlier wish stood on seed \(seed)")
        }
    }
}
