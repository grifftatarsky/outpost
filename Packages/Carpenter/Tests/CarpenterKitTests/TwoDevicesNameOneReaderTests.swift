@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "Two of Alice's devices name Dave the reader of her space for him in one round", .serialized,
    .timeLimit(.minutes(10)), .tags(.sync, .manyDevices))
struct TwoDevicesNameOneReaderTests {
    @Test(
        "Alice's tablet loses the race to name Dave, and Dave still has one space of hers, read by him alone",
        arguments: [["Alice", "Alice's tablet", "Dave"], ["Alice's tablet", "Alice", "Dave"]])
    func oneSpaceForDave(order: [String]) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Dave")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob"])
        try await g.secondDevice("Alice's tablet", of: "Alice")
        let everyone = ["Alice", "Alice's tablet", "Bob", "Dave"]

        await g.door("Alice's tablet").fail(.space, to: g.id("Dave"))
        let invite = try await g["Alice"].invite(
            joinerCode: await g["Dave"].joinerCode(through: g.door("Dave")), joining: room, through: g.door("Alice"))
        try await g["Dave"].redeem(inviteCode: try invite.encoded())
        for _ in 0..<5 { await g.takeTurns(order) }
        try await g.settle()
        try #require(
            await g.door("Alice's tablet").faultsPending == 0, "precondition: the tablet's naming of Dave failed once")
        try #require(
            await g.callsByName("Alice's tablet").filter { $0 == "space Dave" }.count >= 2,
            "precondition: the tablet asked for Dave's space again after it failed")

        try await g["Alice"].send("Alice to Dave", to: room)
        try await g["Dave"].send("Dave to Alice", to: room)
        try await g.settle()

        let davesAccount = LocalPairStore.account(of: g.id("Dave"))
        let alicesSpaces = await g.cloud.view().spaces.values.filter { $0.owner == g.id("Alice") }
        let namingDave = alicesSpaces.filter { $0.named == davesAccount }
        let readByDave = alicesSpaces.filter { $0.joined.contains(davesAccount) }
        #expect(namingDave.count == 1, "Alice has \(namingDave.count) spaces naming Dave as their reader")
        #expect(readByDave.count == 1, "Dave reads \(readByDave.count) of Alice's spaces")
        #expect(
            readByDave.allSatisfy { $0.joined == [davesAccount] }, "somebody besides Dave reads Alice's space for him")
        for name in everyone {
            for body in ["Alice to Dave", "Dave to Alice"] {
                #expect(g.shows(body, in: room, on: name), "\(name) never read \"\(body)\"")
            }
        }
        g.sameRoom(room, on: everyone)
    }
}
