@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A hole and a block among five", .serialized, .timeLimit(.minutes(10)), .tags(.sync, .manyDevices))
struct AHoleAndABlockAmongFiveTests {
    private static let everyone = ["Alice", "Bob", "Carol", "Dave", "Erin"]

    @Test(
        "A message Erin never got is filled in by whichever friend holds it while Alice, who wrote it, is away",
        arguments: ["Bob", "Carol", "Dave"])
    func aHoleIsFilledByWhoeverHoldsIt(holder: String) async throws {
        let g = try await Gathering.of(Self.everyone)
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])

        var forErin: [[PacketID]] = []
        for word in ["first", "second", "third"] {
            let before = Set(await g.cloud.writtenPackets)
            try await g["Alice"].send(word, to: room)
            await g.takeTurns("Alice", "Bob", "Carol", "Dave")
            let sent = await g.cloud.everySentPacket
            forErin.append(
                await g.cloud.writtenPackets.filter { !before.contains($0) && sent[$0]?.to == g.id("Erin") })
        }
        try #require(forErin.allSatisfy { !$0.isEmpty }, "precondition: each message went to Erin in its own round")
        let holesBefore = g["Erin"].missingHistory(in: room).total
        for packet in forErin[1] {
            await lose(packet, from: g.cloud, sentBy: ["Alice", "Bob", "Carol", "Dave"].map { g[$0] })
        }
        await g.takeTurns("Erin")
        try #require(
            g["Erin"].missingHistory(in: room).total == holesBefore + 1,
            "precondition: Erin is missing one more message")
        try #require(!g.shows("second", in: room, on: "Erin"), "precondition: Erin never read \"second\"")
        try #require(g.shows("second", in: room, on: holder), "precondition: \(holder) holds \"second\"")

        let others = ["Bob", "Carol", "Dave"].filter { $0 != holder }
        g.away("Alice")
        for name in others { g.away(name) }
        _ = try #require(await g["Erin"].startRepair(in: room), "precondition: Erin started a repair")
        try await g.settle()

        #expect(g.shows("second", in: room, on: "Erin"), "Erin never got \"second\" from \(holder)")
        #expect(g["Erin"].missingHistory(in: room).isEmpty, "Erin still misses history after \(holder) answered")
        let status = try #require(g["Erin"].repairStatus(of: room), "Erin's repair was forgotten")
        #expect(status.answered.map(\.id).contains(g.id(holder)), "\(holder) never answered Erin's repair")
        #expect(!status.answered.map(\.id).contains(g.id("Alice")), "Alice answered while she was away")
        #expect(status.recovered == 1, "Erin's repair says it recovered \(status.recovered), not one")

        g.back("Alice")
        for name in others { g.back(name) }
        try await g.settle()
        g.sameRoom(room, on: Self.everyone)
        for name in Self.everyone {
            #expect(g[name].missingHistory(in: room).isEmpty, "\(name) misses history once everybody is back")
        }
    }

    @Test(
        "After Carol blocks Dave and unblocks him, what he wrote meanwhile reaches her and what she writes reaches him",
        arguments: 0..<5)
    func messagesCrossBothWaysAfterAnUnblock(rotation: Int) async throws {
        let g = try await Gathering.of(Self.everyone)
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])
        let order = Array(Self.everyone[rotation...] + Self.everyone[..<rotation])

        await g["Carol"].block(g.id("Dave"))
        try await g.settle(inOrder: order)
        for word in ["one", "two"] {
            try await g["Dave"].send("Dave during the block, \(word)", to: room)
            try await g.settle(inOrder: order)
        }
        for word in ["one", "two"] {
            let body = "Dave during the block, \(word)"
            #expect(!g.shows(body, in: room, on: "Carol"), "Carol, blocking Dave, was shown \"\(body)\"")
            for name in ["Alice", "Bob", "Erin"] {
                #expect(g.shows(body, in: room, on: name), "\(name) never read \"\(body)\"")
            }
        }

        await g["Carol"].unblock(g.id("Dave"))
        try await g.settle(inOrder: order)
        try await g["Carol"].send("Carol after the unblock", to: room)
        try await g["Dave"].send("Dave after the unblock", to: room)
        try await g.settle(inOrder: order)

        for word in ["one", "two"] {
            let body = "Dave during the block, \(word)"
            #expect(g.shows(body, in: room, on: "Carol"), "Carol never read \"\(body)\" after unblocking Dave")
        }
        #expect(g.shows("Carol after the unblock", in: room, on: "Dave"), "Dave never read Carol after the unblock")
        #expect(g.shows("Dave after the unblock", in: room, on: "Carol"), "Carol never read Dave after the unblock")
        g.sameRoom(room, on: Self.everyone)
    }

    @Test("While Carol blocks Dave, what she writes in a room of five does not reach him", arguments: 0..<5)
    func whatTheBlockerWritesDoesNotReachTheBlocked(rotation: Int) async throws {
        let g = try await Gathering.of(Self.everyone)
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])
        let order = Array(Self.everyone[rotation...] + Self.everyone[..<rotation])

        await g["Carol"].block(g.id("Dave"))
        try await g.settle(inOrder: order)
        try await g["Carol"].send("Carol during the block", to: room)
        try await g.settle(inOrder: order)

        for name in ["Alice", "Bob", "Erin"] {
            #expect(g.shows("Carol during the block", in: room, on: name), "\(name) never read Carol")
        }
        withKnownIssue("Dave, blocked by Carol, reads what she writes, because the other members pass it on") {
            #expect(!g.shows("Carol during the block", in: room, on: "Dave"), "Dave, blocked, read Carol")
        }
    }
}
