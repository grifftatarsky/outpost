@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "A removed member's quiet rounds write nothing", .serialized, .timeLimit(.minutes(10)),
    .tags(.membership, .manyDevices))
struct ARemovedMembersQuietRoundsWriteNothingTests {
    @Test(
        "Once everything has settled, a member who was removed or who left puts nothing in iCloud",
        arguments: [(false, false), (true, false), (false, true)])
    func aMemberWhoIsOutPutsNothing(somebodyIsAway: Bool, erinLeaves: Bool) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Erin"])
        if somebodyIsAway { g.away("Carol") }
        if erinLeaves {
            try await g["Erin"].leave(room)
        } else {
            try await g["Alice"].remove(g.id("Erin"), from: room)
        }
        try await g.settle()

        let (before, bobBefore) = (await g.door("Erin").calls.count, await g.door("Bob").calls.count)
        for _ in 0..<3 { await g.takeTurns("Alice", "Bob", "Carol", "Erin") }
        let puts = await g.door("Erin").calls.dropFirst(before).count { $0.call == .put }
        let bobsPuts = await g.door("Bob").calls.dropFirst(bobBefore).count { $0.call == .put }
        #expect(bobsPuts == 0, "the control: Bob, still in the room, put \(bobsPuts) packets in three quiet rounds")
        let owed = g["Erin"].confirmationsOwed().count
        #expect(puts == 0, "Erin put \(puts) packets in three quiet rounds, owing \(owed) confirmation(s)")
    }
}
