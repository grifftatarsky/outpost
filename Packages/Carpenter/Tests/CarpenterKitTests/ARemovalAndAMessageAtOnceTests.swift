@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "A removal and a message at the same moment", .serialized, .timeLimit(.minutes(10)),
    .tags(.membership, .manyDevices))
struct ARemovalAndAMessageAtOnceTests {
    struct Collecting: CustomTestStringConvertible, Sendable {
        let erinFirst: [Bool]

        var testDescription: String {
            zip(["Bob", "Carol", "Dave"], erinFirst).map { "\($0) from \($1 ? "Erin" : "Alice") first" }
                .joined(separator: ", ")
        }

        static let all = (0..<8).map { bits in Collecting(erinFirst: (0..<3).map { bits & (1 << $0) != 0 }) }
    }

    @Test("A message the remover had not collected is shown nowhere, whoever hears which first",
        arguments: Collecting.all)
    func aMessageTheRemoverHadNotSeenIsShownNowhere(collecting: Collecting) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])

        try await g["Erin"].send("m1", to: room)
        await g.takeTurns("Erin", "Alice")
        try #require(g.shows("m1", in: room, on: "Alice"), "precondition: Alice collected m1")
        try await g["Erin"].send("m2", to: room)
        await g.takeTurns("Erin")
        try await g["Alice"].remove(g.id("Erin"), from: room)
        await g.takeTurns("Alice")

        let (alice, erin) = (g.id("Alice"), g.id("Erin"))
        for (name, erinFirst) in zip(["Bob", "Carol", "Dave"], collecting.erinFirst) {
            for person in erinFirst ? [erin, alice] : [alice, erin] {
                _ = try? await g[name].sync(through: g.door(name), mode: .readOnly, from: [person])
            }
        }
        try await g.settle()

        let stay = ["Alice", "Bob", "Carol", "Dave"]
        g.sameRoom(room, on: stay)
        for name in stay {
            #expect(g.shows("m1", in: room, on: name), "\(name) lost m1, sent before the removal and collected")
            #expect(!g.shows("m2", in: room, on: name), "\(name) shows m2, which the remover had not collected")
        }
        #expect(g["Erin"].roster(of: room).removal(of: erin) != nil, "Erin was never shown her removal")
    }
}
