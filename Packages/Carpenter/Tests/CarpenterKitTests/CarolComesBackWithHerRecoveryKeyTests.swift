@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "Carol comes back with her recovery key", .serialized, .timeLimit(.minutes(10)),
    .tags(.crypto, .manyDevices))
struct CarolComesBackWithHerRecoveryKeyTests {
    @Test(
        "Carol restores onto a new phone while Dave is away, and only the new phone reads what is said next",
        arguments: ["Alice", "Bob", "Erin"])
    func onlyTheNewPhoneReadsWhatIsSaidNext(reachedFirst: String) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])
        await g["Bob"].setToldAboutRestores(true)
        await g["Bob"].setHoldsHistoryForRestores(true)
        try await g.settle()
        let oldPhoneHeld = try #require(g["Carol"].chains[room])
        let recoveryKey = try #require(g["Carol"].recoveryKeyText())

        g.away("Carol", "Dave")
        g.advance(by: 3_600)
        try await g.restoredDevice("Carol's new phone", of: "Carol", fromRecoveryKey: recoveryKey)
        for friend in ["Alice", "Bob", "Erin"] where friend != reachedFirst {
            await g.door("Carol's new phone").cannotReach(g.id(friend))
        }
        await g.takeTurns("Carol's new phone", reachedFirst)
        await g.door("Carol's new phone").reachesEveryone()
        try await g["Alice"].remove(g.id("Erin"), from: room)
        try await g.settle()
        g.back("Dave")
        try await g.settle()

        let senders = ["Alice", "Bob", "Dave"]
        for sender in senders { try await g[sender].send("\(sender), after Carol came back", to: room) }
        try await g.settle()

        for sender in senders {
            let entry = try #require(g.entry(saying: "\(sender), after Carol came back", in: room, on: sender))
            #expect(entry.opened(using: oldPhoneHeld) == nil, "the lost phone's keys open \(sender)'s message")
        }
        #expect(g["Erin"].roster(of: room).removal(of: g.id("Erin")) != nil, "Erin was never shown she was removed")
        #expect(!g.shows("Alice, after Carol came back", in: room, on: "Erin"), "Erin, removed, read Alice's message")

        let newPhone = g.device("Carol's new phone")
        await withKnownIssue("A phone restored from a recovery key, with the old phone gone, never reaches a friend") {
            try await g["Carol's new phone"].send("Carol, on her new phone", to: room)
            try await g.settle()
            g.sameRoom(room, on: senders + ["Carol's new phone"])
            for sender in senders {
                #expect(
                    g.shows("\(sender), after Carol came back", in: room, on: "Carol's new phone"),
                    "Carol's new phone never read \(sender)'s message")
                #expect(
                    g.shows("Carol, on her new phone", in: room, on: sender), "\(sender) never read Carol's new phone")
            }
            let carols = try #require(g.entry(saying: "Carol, on her new phone", in: room, on: "Carol's new phone"))
            #expect(carols.opened(using: oldPhoneHeld) == nil, "the lost phone's keys open what the new phone wrote")
            for friend in ["Alice", "Bob", "Dave", "Erin"] {
                let listed = g.devices(of: "Carol", seenBy: friend)
                #expect(listed == [newPhone], "\(friend) lists \(listed.count) devices for Carol, not one")
            }
        }
    }
}
