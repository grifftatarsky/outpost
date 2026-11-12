@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Five people join one at a time", .serialized, .timeLimit(.minutes(10)), .tags(.membership, .manyDevices))
struct FivePeopleJoinOneAtATimeTests {
    nonisolated static let everyone = ["Alice", "Bob", "Carol", "Dave", "Erin"]
    nonisolated static let rotations = everyone.indices.map { Array(everyone[$0...] + everyone[..<$0]) }

    @Test(
        "Answers that a link is not ready yet, and Carol opening the app twice, make no space nobody reads",
        arguments: rotations)
    func notReadyAnswersAndRelaunchesMakeNoExtraSpace(order: [String]) async throws {
        let g = try await Gathering.of(Self.everyone)
        let room = try await g["Alice"].createRoom(named: "Lanterns")
        try await admit("Bob", by: "Alice", to: room, in: g, order: order)
        try await admit("Carol", by: "Bob", to: room, in: g, order: order)
        try await admit("Dave", by: "Carol", to: room, in: g, order: order)
        await g.door("Erin").answerJoinNotYetNamed(times: 2)
        try await admit("Erin", by: "Alice", to: room, in: g, order: order)
        #expect(await g.door("Erin").faultsPending == 0, "Erin was never told a link was not ready")
        let joinsByErin = await g.door("Erin").calls.count { $0.call == .join }
        try #require(joinsByErin > 2, "precondition: Erin asked to join again after being told twice it was not ready")

        let carolsSpaces = await g.cloud.spaceCount(of: g.id("Carol"))
        await g.relaunch("Carol")
        try await g.settle(inOrder: order)
        let afterFirst = await g.cloud.spaceCount(of: g.id("Carol"))
        try await g["Carol"].send("Carol, opened once more", to: room)
        try await g.settle(inOrder: order)
        await g.relaunch("Carol")
        try await g.settle(inOrder: order)
        let afterSecond = await g.cloud.spaceCount(of: g.id("Carol"))
        #expect(afterFirst == carolsSpaces, "Carol's first relaunch made her \(carolsSpaces) spaces \(afterFirst)")
        #expect(afterSecond == carolsSpaces, "Carol's second relaunch made her \(carolsSpaces) spaces \(afterSecond)")

        for person in Self.everyone { try await g[person].send("\(person) is here", to: room) }
        try await g.settle(inOrder: order)

        g.sameRoom(room, on: Self.everyone)
        for viewer in Self.everyone {
            #expect(g[viewer].roster(of: room).members.count == 5, "\(viewer) does not show five people in Lanterns")
            for person in Self.everyone {
                #expect(g.shows("\(person) is here", in: room, on: viewer), "\(viewer) never read \(person)'s message")
            }
        }
        for owner in Self.everyone {
            let read = await g.cloud.readers(ofSpaceOf: g.id(owner)).filter { !$0.isEmpty }
            #expect(read.allSatisfy { $0.count == 1 }, "a space of \(owner)'s is read by more than one person: \(read)")
            let others = Set(Self.everyone.filter { $0 != owner }.map { LocalPairStore.account(of: g.id($0)) })
            #expect(read.count == others.count, "\(owner) has \(read.count) spaces somebody reads, not one per friend")
            #expect(
                read.reduce(Set<String>()) { $0.union($1) } == others,
                "\(owner)'s spaces are not read by exactly the four people \(owner) talks to")
            let unread = await g.cloud.spaceCount(of: g.id(owner)) - read.count
            #expect(unread <= 1, "\(owner) keeps \(unread) spaces nobody reads, more than the one a code offers")
        }
    }

    private func admit(
        _ joiner: String, by inviter: String, to room: RoomID, in g: Gathering, order: [String]
    ) async throws {
        let code = await g[joiner].joinerCode(through: g.door(joiner))
        let invite = try await g[inviter].invite(joinerCode: code, joining: room, through: g.door(inviter))
        try await g[joiner].redeem(inviteCode: try invite.encoded())
        try await g.settle(inOrder: order)
        try #require(
            g[inviter].roster(of: room).members.contains(g.id(joiner)),
            "precondition: \(inviter) shows \(joiner) in the room")
    }
}
