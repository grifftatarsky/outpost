@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A write whose answer was lost", .serialized, .timeLimit(.minutes(10)), .tags(.sync, .manyDevices))
struct AWriteWhoseAnswerWasLostTests {
    @Test(
        "A packet and a receipt that landed while their answers were lost are not made twice", arguments: [false, true])
    func aWriteThatLandedIsNotMadeTwice(answersAreLost: Bool) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol"])

        try await g["Alice"].send("once", to: room)
        if answersAreLost {
            await g.door("Alice").fail(.put, landing: true)
            await g.door("Bob").fail(.acknowledge, landing: true)
        }
        let (aliceBefore, bobBefore) = (await g.door("Alice").calls.count, await g.door("Bob").calls.count)
        await g.takeTurns("Alice", "Bob", "Carol")
        #expect(await g.door("Alice").faultsPending + g.door("Bob").faultsPending == 0, "a lost answer never happened")
        try await g.settle()
        let alicePut = await g.door("Alice").calls.dropFirst(aliceBefore).filter { $0.call == .put }
        for friend in ["Bob", "Carol"] {
            let puts = alicePut.count { $0.peer == g.id(friend) }
            #expect(puts == 1, "Alice wrote \(puts) packets to \(friend) for one message")
        }
        let bobsAcknowledged = await g.door("Bob").calls.dropFirst(bobBefore).filter { $0.call == .acknowledge }
        let acknowledgedTwice = bobsAcknowledged.count - Set(bobsAcknowledged.compactMap(\.packet)).count
        #expect(acknowledgedTwice == 0, "Bob answered \(acknowledgedTwice) packets twice")
        #expect(!bobsAcknowledged.isEmpty, "Bob answered nothing")
        try await g["Bob"].send("once from Bob", to: room)
        try await g.settle()

        for name in ["Alice", "Bob", "Carol"] {
            for body in ["once", "once from Bob"] {
                let shown = g[name].messages(in: room).count { $0.body == body }
                #expect(shown == 1, "\(name) shows \"\(body)\" \(shown) times")
            }
        }
        g.sameRoom(room, on: ["Alice", "Bob", "Carol"])
        let unanswered = await g.cloud.everySentPacket.values.filter { $0.receipts.isEmpty }
        #expect(unanswered.isEmpty, "\(unanswered.count) packets were left in iCloud with no receipt")
        let acknowledged = await g.cloud.everySentPacket.count
        #expect(acknowledged == 0, "\(acknowledged) packets stayed in iCloud after they were acknowledged")

        g.advance(by: AppSession.packetIsOrphanedAfter + 60)
        try await g["Alice"].send("nine days on", to: room)
        try await g.settle()
        let stillThere = await g.cloud.everySentPacket.count
        #expect(stillThere == 0, "\(stillThere) acknowledged packets were never swept")
    }
}
