@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "A second device sends after what its member collected", .serialized, .timeLimit(.minutes(10)),
    .tags(.membership, .manyDevices))
struct ASecondDeviceSendsAfterWhatItsMemberCollectedTests {
    @Test("A tablet that sends before device sync tells it of a removal does not write under the removed key")
    func aTabletBehindItsPhoneDoesNotWriteUnderTheRemovedKey() async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Erin"])
        try await g.secondDevice("Bob's tablet", of: "Bob")
        let erinHeld = try #require(g["Erin"].chains[room])

        try await g["Alice"].remove(g.id("Erin"), from: room)
        await g.takeTurns("Alice", "Bob")
        try #require(
            g["Bob"].roster(of: room).removal(of: g.id("Erin")) != nil,
            "precondition: Bob's phone collected the removal")
        try await g["Bob's tablet"].send("from the tablet", to: room, after: g.door("Bob's tablet"))
        try await g.settle()

        let sent = try #require(g.entry(saying: "from the tablet", in: room, on: "Bob's tablet"))
        #expect(sent.opened(using: erinHeld) == nil, "Erin's keys from before her removal open the tablet's message")
        #expect(!g.shows("from the tablet", in: room, on: "Erin"), "Erin read the tablet's message")
        g.sameRoom(room, on: ["Alice", "Carol", "Bob", "Bob's tablet"])
        #expect(g.shows("from the tablet", in: room, on: "Alice"))
    }

    @Test("A phone that could not store a removal for its tablet leaves the delivery for the tablet to collect")
    func aPhoneThatCouldNotTellItsTabletDoesNotSignForTheDelivery() async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Erin"])
        try await g.secondDevice("Bob's tablet", of: "Bob")
        let erinHeld = try #require(g["Erin"].chains[room])

        try await g["Alice"].remove(g.id("Erin"), from: room)
        await g.find("Bob").engine.cut()
        await g.takeTurns("Alice", "Bob")
        try #require(
            g["Bob"].roster(of: room).removal(of: g.id("Erin")) != nil,
            "precondition: Bob's phone collected the removal")
        try await g["Bob's tablet"].send("from the tablet", to: room, after: g.door("Bob's tablet"))

        let sent = try #require(g.entry(saying: "from the tablet", in: room, on: "Bob's tablet"))
        #expect(sent.opened(using: erinHeld) == nil, "Erin's keys from before her removal open the tablet's message")
        #expect(
            g["Bob's tablet"].roster(of: room).removal(of: g.id("Erin")) != nil,
            "the tablet wrote without hearing of the removal its phone had collected")
    }
}
