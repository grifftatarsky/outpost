@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "What arrives before what it answers", .serialized, .timeLimit(.minutes(10)), .tags(.sync, .manyDevices))
struct WhatArrivesBeforeWhatItAnswersTests {
    @Test(
        "A reply, an edit, a reaction and a key that arrive a round before what they depend on all apply",
        arguments: [["Bob", "Carol", "Erin"], ["Erin", "Carol", "Bob"], ["Carol", "Bob", "Erin"]])
    func everythingThatArrivedEarlyApplies(othersInOrder: [String]) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])

        g.away("Dave")
        await g.door("Alice").cannotReach(g.id("Dave"))
        try await g["Alice"].send("the boat leaves at six", to: room)
        await g.takeTurns("Alice", "Bob", "Carol", "Erin")
        let writtenBeforeTheEdit = Set(await g.cloud.writtenPackets)
        let original = try #require(g["Alice"].messages(in: room).last, "precondition: Alice shows her message")
        try await g["Alice"].edit(original.id, to: "the boat leaves at seven")
        let theEdit = try #require(g["Alice"].head?.hash, "precondition: Alice wrote her edit down")
        await g.takeTurns("Alice", "Bob", "Carol", "Erin")
        let edited = try #require(
            g["Bob"].messages(in: room).first { $0.id == original.id && $0.isEdited },
            "precondition: Bob shows Alice's edited message")
        try await g["Bob"].react(to: edited.id, in: room, with: "👍")
        try await g["Bob"].send("seven works for me", to: room)
        await g.takeTurns("Bob")
        try await g["Alice"].remove(g.id("Erin"), from: room)
        await g.takeTurns("Alice", "Carol")
        let alicesKey = try #require(g.key(of: room, on: "Alice"))
        try #require(g.key(of: room, on: "Carol") == alicesKey, "precondition: Carol took the key Alice made")
        try await g["Carol"].send("I'll bring the oars", to: room)
        await g.takeTurns("Carol")
        let carols = try #require(g.entry(saying: "I'll bring the oars", in: room, on: "Carol"))
        let alicesOnly = try #require(g.chainHoldingOnlyTheWritingKey(of: room, on: "Alice"))
        try #require(carols.opened(using: alicesOnly) != nil, "precondition: Carol wrote under the key Alice made")

        for id in writtenBeforeTheEdit where await g.cloud.everySentPacket[id]?.to == g.id("Dave") {
            await g.door("Dave").skip(id)
        }
        g.back("Dave")
        await g.takeTurns("Dave")
        let davesEntries = Set(g["Dave"].replica.allEntries.map(\.hash))
        try #require(
            !davesEntries.contains(original.id.entry), "precondition: Dave has not collected Alice's message")
        try #require(
            davesEntries.contains(carols.hash), "precondition: Dave collected Carol's message before Alice's key")
        let bobsReply = try #require(g.entry(saying: "seven works for me", in: room, on: "Bob"))
        try #require(davesEntries.contains(bobsReply.hash), "precondition: Dave collected Bob's reply before Alice's")
        try #require(davesEntries.contains(theEdit), "precondition: Dave collected Alice's edit before her message")
        await g.door("Alice").reachesEveryone()
        try await g.settle(inOrder: ["Alice"] + othersInOrder + ["Dave"])

        let shown = g["Dave"].messages(in: room)
        let message = shown.first { $0.id == original.id }
        #expect(
            message?.body == "the boat leaves at seven", "Dave shows \(message?.body ?? "nothing") for Alice's message")
        #expect(message?.isEdited == true, "Dave does not show Alice's message as edited")
        #expect(message?.reactions["👍"]?.contains(g.id("Bob")) == true, "Dave does not show Bob's reaction")
        let bodies = shown.map(\.body)
        let messageAt = bodies.firstIndex(of: "the boat leaves at seven")
        let replyAt = bodies.firstIndex(of: "seven works for me")
        #expect(replyAt != nil, "Dave never shows Bob's reply")
        #expect(
            messageAt.flatMap { at in replyAt.map { at < $0 } } == true,
            "Dave shows Bob's reply before what it answers")
        #expect(g.shows("I'll bring the oars", in: room, on: "Dave"), "Dave cannot read Carol's message")
        #expect(g.key(of: room, on: "Dave") == alicesKey, "Dave does not write under the key Alice made")
        #expect(!g.shows("I'll bring the oars", in: room, on: "Erin"), "Erin, removed, read Carol's message")
        g.sameRoom(room, on: ["Alice", "Bob", "Carol", "Dave"])
    }
}
