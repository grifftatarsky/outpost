@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Away while the key changes", .serialized, .timeLimit(.minutes(10)), .tags(.membership, .manyDevices))
struct AwayWhileTheKeyChangesTests {
    @Test(
        "A room's key changes twice while Dave is away, and his first message back is sealed under the newest",
        arguments: ["Alice", "Bob", "Carol"], [false, true])
    func davesFirstMessageBackIsSealedUnderTheNewestKey(late: String, sendFailsSilently: Bool) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])
        try await g.secondDevice("Bob's tablet", of: "Bob")

        g.away("Dave")
        await g.door(late).cannotReach(g.id("Dave"))
        try await g["Alice"].remove(g.id("Erin"), from: room)
        await g.takeTurns("Alice", "Bob", "Carol", "Erin")
        try await g["Alice"].send("after Erin", to: room)
        try await g["Bob"].send("Bob after Erin", to: room)
        await g.takeTurns("Alice", "Bob", "Carol", "Bob's tablet")

        let tabletHeld = try #require(g["Bob's tablet"].chains[room])
        try #require(
            g.key(of: room, on: "Bob's tablet") == g.key(of: room, on: "Bob"),
            "precondition: the tablet holds the key from Erin's removal")
        await g.relay(of: "Bob").failNextSend(silently: sendFailsSilently)
        await g.relay(of: "Bob").failNextRefresh()
        try await g["Bob"].revoke(g.device("Bob's tablet"))
        try await g.quiesce()
        let keyAtTheRevoke = try #require(g.chainHoldingOnlyTheWritingKey(of: room, on: "Bob"))
        try #require(
            g.key(of: room, on: "Bob") != g.key(of: room, on: "Bob's tablet"),
            "precondition: removing the tablet changed the key")
        await g.takeTurns("Bob", "Alice", "Carol")
        try await g["Carol"].send("Carol after the tablet", to: room)
        try await g.settle(inOrder: ["Alice", "Bob", "Carol", "Erin", "Bob's tablet"])
        #expect(await g.relay(of: "Bob").failuresPending == 0, "a device sync fault never fired")

        g.back("Dave")
        await g.takeTurns("Dave")
        await g.door(late).reachesEveryone()
        try await g["Dave"].send("Dave is back", to: room, after: g.door("Dave"))
        try await g.settle(inOrder: ["Dave", "Alice", "Bob", "Carol", "Erin", "Bob's tablet"])

        g.sameRoom(room, on: ["Alice", "Bob", "Carol", "Dave"])
        for body in ["after Erin", "Bob after Erin", "Carol after the tablet", "Dave is back"] {
            #expect(g.shows(body, in: room, on: "Dave"), "Dave never read \"\(body)\"")
            #expect(!g.shows(body, in: room, on: "Erin"), "Erin, removed, read \"\(body)\"")
            let entry = try #require(g.entry(saying: body, in: room, on: "Alice"))
            #expect(entry.opened(using: try #require(g["Erin"].chains[room])) == nil, "Erin's keys open \"\(body)\"")
        }
        let davesMessage = try #require(g.entry(saying: "Dave is back", in: room, on: "Bob"))
        #expect(
            davesMessage.opened(using: tabletHeld) == nil, "the removed tablet's keys open Dave's first message back")
        #expect(
            davesMessage.opened(using: keyAtTheRevoke) != nil,
            "Dave's first message back is not sealed under the key Bob made when he removed the tablet")
        #expect(!g.shows("Dave is back", in: room, on: "Bob's tablet"), "the removed tablet read Dave's message")
        #expect(g.devices(of: "Bob", seenBy: "Dave").count == 1, "Dave still lists Bob's removed tablet")
        #expect(g["Erin"].roster(of: room).removal(of: g.id("Erin")) != nil, "Erin was never shown she was removed")
    }

    @Test(
        "A friend away longer than a packet waits still gets the new key when he comes back",
        arguments: [false, true])
    func aFriendAwayLongerThanAPacketWaitsStillGetsTheKey(aliceRelaunches: Bool) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])

        g.away("Dave")
        try await g["Alice"].remove(g.id("Erin"), from: room)
        try await g.settle()
        let removedAt = g.iCloud.now
        try #require(
            await g.cloud.everySentPacket.values.contains { $0.to == g.id("Dave") },
            "precondition: packets wait for Dave")
        g.advance(by: SyncSession.packetWaitsFor + 3_600)
        try await g.settle()
        let oldPacketsForDave = await g.cloud.everySentPacket.values.filter {
            $0.to == g.id("Dave") && ($0.createdAt ?? .distantPast) <= removedAt
        }
        try #require(oldPacketsForDave.isEmpty, "precondition: every packet waiting for Dave expired and was withdrawn")
        if aliceRelaunches { await g.relaunch("Alice") }

        g.back("Dave")
        try await g.settle()
        try await g["Alice"].send("after Dave's long absence", to: room)
        try await g.settle()
        try await g["Dave"].send("Dave back", to: room)
        try await g.settle()

        let erinHeld = try #require(g["Erin"].chains[room])
        let davesMessage = try #require(g.entry(saying: "Dave back", in: room, on: "Dave"))
        withKnownIssue("a key handed out in a packet that expired is not offered again until a relaunch") {
            #expect(!g.shows("Dave back", in: room, on: "Erin"), "Erin, removed, read Dave's message")
            #expect(davesMessage.opened(using: erinHeld) == nil, "Erin's keys open Dave's message")
            #expect(g.shows("after Dave's long absence", in: room, on: "Dave"), "Dave cannot read Alice's message")
            #expect(g.key(of: room, on: "Dave") == g.key(of: room, on: "Alice"), "Dave writes under an old key")
        } when: {
            !aliceRelaunches
        }
        withKnownIssue("a removal carried only in packets that expired never reaches the friend who was away") {
            #expect(
                g["Dave"].roster(of: room).removal(of: g.id("Erin")) != nil, "Dave never heard that Erin was removed")
            g.sameRoom(room, on: ["Alice", "Bob", "Carol", "Dave"])
        }
    }
}
