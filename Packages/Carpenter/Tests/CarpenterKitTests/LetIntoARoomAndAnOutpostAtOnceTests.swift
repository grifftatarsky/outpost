@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "Let into a room and onto an Outpost at once", .serialized, .timeLimit(.minutes(10)),
    .tags(.membership, .manyDevices))
struct LetIntoARoomAndAnOutpostAtOnceTests {
    @Test("A friend let into a room and onto an Outpost in one round gets both keys, on both devices")
    func bothKeysReachBothDevices() async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol")
        _ = try await g.room("Hearth", host: "Alice", guests: ["Bob"])
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Carol"])
        let wall = g["Alice"].outpostRoom(for: g.id("Alice"))
        try await g["Alice"].send("before Bob", to: nil)
        try await g.settle()

        await g.door("Alice").cannotReach(g.id("Bob"))
        let invite = try await g["Alice"].invite(g.id("Bob"), joining: room, through: g.door("Alice"))
        try await g["Bob"].redeem(inviteCode: try invite.encoded())
        for _ in 0..<5 { await g.takeTurns("Bob", "Alice") }
        try await g["Alice"].allowOutpost(g.id("Bob"), everything: false)
        try #require(
            g["Alice"].roster(of: room).members.contains(g.id("Bob")), "precondition: Alice let Bob into Lanterns")
        try #require(g["Bob"].chains[wall] == nil, "precondition: Bob holds no key to Alice's Outpost yet")

        await g.door("Alice").holdView()
        try await g.secondDevice("Bob's tablet", of: "Bob")
        try #require(
            g.devices(of: "Bob", seenBy: "Alice").count == 1, "precondition: Alice has not heard of Bob's tablet")

        g.away("Bob")
        await g.door("Alice").reachesEveryone()
        let packetsBefore = Set(await g.cloud.writtenPackets)
        await g.takeTurns("Alice")
        var grantsInOnePacket: [Int] = []
        for id in await g.cloud.writtenPackets where !packetsBefore.contains(id) {
            if await g.cloud.everySentPacket[id]?.to == g.id("Bob") {
                grantsInOnePacket.append(await g.cloud.grantCount(in: id))
            }
        }
        try #require(
            grantsInOnePacket.contains(2),
            "precondition: one round of Alice's carried both keys to Bob: \(grantsInOnePacket)")
        await g.takeTurns("Bob's tablet")
        try #require(
            g["Bob's tablet"].chains[wall] == nil && g.key(of: room, on: "Bob's tablet") == nil,
            "precondition: Bob's tablet collected keys sealed for his phone alone and could not open them")
        g.back("Bob")
        await g.takeTurns("Bob", "Bob's tablet")

        for device in ["Bob", "Bob's tablet"] {
            #expect(g.key(of: room, on: device) != nil, "\(device) holds no key to Lanterns before Alice hears of it")
            #expect(g[device].chains[wall] != nil, "\(device) holds no key to Alice's Outpost before she hears of it")
        }

        await g.door("Alice").refreshView()
        try await g.settle()
        try await g["Alice"].send("for Lanterns", to: room)
        try await g["Alice"].send("for my readers", to: nil)
        try await g.settle()

        g.sameRoom(room, on: ["Alice", "Bob", "Bob's tablet", "Carol"])
        for device in ["Bob", "Bob's tablet"] {
            #expect(g.shows("for Lanterns", in: room, on: device), "\(device) never read Alice's message in Lanterns")
            let post = g[device].feed().first { $0.body == "for my readers" }
            #expect(post != nil, "\(device) never read Alice's Outpost post")
            if let post { try await g[device].comment(on: post, text: "from \(device)") }
        }
        try await g.settle()
        let alicesPost = try #require(g["Alice"].outpost().first { $0.body == "for my readers" })
        let comments = g["Alice"].comments(on: alicesPost).map(\.body)
        for device in ["Bob", "Bob's tablet"] {
            #expect(comments.contains("from \(device)"), "Alice never read the comment from \(device)")
        }
    }
}
