@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "A reader removes a device while the Outpost's owner is away", .serialized, .timeLimit(.minutes(10)),
    .tags(.membership, .manyDevices))
struct AReaderRemovesADeviceWhileTheOwnerIsAwayTests {
    @Test(
        "Once Alice hears Bob removed his tablet, her next post does not open on it",
        arguments: [false, true])
    func theOwnersNextPostDoesNotOpenOnTheRemovedTablet(tabletTurnsBetweenThePosts: Bool) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol")
        _ = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol"])
        for reader in ["Bob", "Carol"] { try await g["Alice"].allowOutpost(g.id(reader), everything: true) }
        try await g.settle()
        try await g.secondDevice("Bob's tablet", of: "Bob")
        try await g["Alice"].send("before the removal", to: nil)
        try await g.settle()
        try #require(
            g.reads("before the removal", onTheOutpostOf: "Alice", on: "Bob's tablet"),
            "precondition: Bob's tablet reads Alice's Outpost")
        let tabletHeld = try #require(
            g["Bob's tablet"].chains[g.outpost(of: "Alice")], "precondition: the tablet holds Alice's Outpost keys")

        g.mailboxOnly("Bob's tablet")
        g.away("Alice")
        try await g["Bob"].revoke(g.device("Bob's tablet"))
        await g.door("Bob").cannotReach(g.id("Alice"))
        await g.takeTurns("Bob", "Carol", "Bob's tablet")
        g.back("Alice")
        await g.takeTurns("Alice")
        try #require(
            g.devices(of: "Bob", seenBy: "Alice").count == 2, "precondition: Alice has not heard of the removal")
        try await g["Alice"].send("first post back", to: nil)
        await g.takeTurns("Alice")

        await g.door("Bob").reachesEveryone()
        await g.takeTurns("Bob", "Alice")
        try #require(g.devices(of: "Bob", seenBy: "Alice").count == 1, "precondition: Alice heard of the removal")
        if tabletTurnsBetweenThePosts { await g.takeTurns("Bob's tablet") }
        try await g["Alice"].send("second post back", to: nil)
        try await g.settle()

        let second = try #require(g.entry(ofPostSaying: "second post back", by: "Alice"))
        #expect(second.opened(using: tabletHeld) == nil, "the tablet's old keys open Alice's second post")
        #expect(
            !g.reads("second post back", onTheOutpostOf: "Alice", on: "Bob's tablet"),
            "the removed tablet read Alice's second post")
        for reader in ["Bob", "Carol"] {
            for body in ["first post back", "second post back"] {
                #expect(g.reads(body, onTheOutpostOf: "Alice", on: reader), "\(reader) never read \"\(body)\"")
            }
        }
        for viewer in ["Alice", "Carol"] {
            #expect(g.devices(of: "Bob", seenBy: viewer).count == 1, "\(viewer) still lists Bob's removed tablet")
        }
    }
}
