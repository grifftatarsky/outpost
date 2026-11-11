@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A round cut short loses nothing", .serialized, .timeLimit(.minutes(10)), .tags(.sync, .manyDevices))
struct ARoundCutShortLosesNothingTests {
    nonisolated static let callsInCarolsRound = 1...24
    nonisolated static let callsInCarolsThrottledRound = 1...24
    nonisolated static let callsInBobsRound = 1...31
    nonisolated static let callsInAlicesRoundAfterARemoval = 1...27

    private func everyMessageOnce(in room: RoomID, on name: String, of g: Gathering, _ bodies: [String]) {
        let shown = g[name].messages(in: room).map(\.body)
        for body in bodies {
            #expect(shown.count { $0 == body } == 1, "\(name) shows \"\(body)\" \(shown.count { $0 == body }) times")
        }
    }

    @Test("Carol's app ends at a call of a round; reopened, nothing she acknowledged is missing from her disk",
        arguments: callsInCarolsRound)
    func carolsAppEndsMidRound(call: Int) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave"])
        var sentToCarol: [PacketID: Set<EntryHash>] = [:]
        for name in ["Alice", "Bob", "Dave"] {
            try await g[name].send("from \(name)", to: room)
            let report = try await g.takeTurns(name)[name]?.get()
            for packet in report?.written ?? [] where packet.to == g.id("Carol") {
                sentToCarol[packet.packet] = packet.entries
            }
        }

        let ended = await g.endProcess(of: "Carol", atCall: call)
        await g.takeTurns("Carol")
        let iCloudThen = await ended.iCloud
        #expect(iCloudThen != nil, "Carol's round has fewer than \(call) calls, so her app never ended")
        await g.relaunch("Carol")
        let held = Set(g["Carol"].replica.allEntries.map(\.hash))
        let lastCalls = await g.callsByName("Carol").prefix(call).suffix(3)
        if let iCloudThen {
            let carol = g.id("Carol")
            let receipted = iCloudThen.allRecords.compactMap { record -> PacketID? in
                guard iCloudThen.spaces[record.url]?.owner == carol else { return nil }
                return PairWire.packet(fromReceiptName: record.name)
            }
            for packet in receipted {
                let carried = sentToCarol[packet] ?? []
                #expect(
                    carried.isSubset(of: held),
                    "Carol acknowledged a packet whose entries are not on her disk, at call \(call): \(lastCalls)")
            }
        }

        try await g.settle()
        g.sameRoom(room, on: ["Alice", "Carol"])
        everyMessageOnce(in: room, on: "Carol", of: g, ["from Alice", "from Bob", "from Dave"])
    }

    @Test("A round cut off by a throttle after any number of calls loses nothing and repeats nothing",
        arguments: callsInCarolsThrottledRound)
    func aThrottleMidRoundLosesNothing(call: Int) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave"])
        let invite = try await g["Alice"].invite(
            joinerCode: await g["Erin"].joinerCode(through: g.door("Erin")), joining: room, through: g.door("Alice"))
        try await g["Erin"].redeem(inviteCode: try invite.encoded())
        await g.takeTurns("Alice", "Erin", "Alice")
        let people = ["Alice", "Bob", "Carol", "Dave", "Erin"]
        var bodies: [String] = []
        for name in people where g[name].roster(of: room).members.contains(g.id(name)) {
            try await g[name].send("from \(name)", to: room)
            bodies.append("from \(name)")
        }
        try #require(bodies.contains("from Carol"), "precondition: Carol is in the room and wrote")

        let before = await g.door("Carol").calls.count
        await g.door("Carol").stopAnswering(after: call)
        await g.takeTurns("Carol", "Alice", "Bob", "Dave", "Erin")
        #expect(await g.door("Carol").calls.count - before > call, "Carol's round ended before the throttle began")
        await g.door("Carol").relent()
        try await g.settle()

        g.sameRoom(room, on: people)
        for name in people { everyMessageOnce(in: room, on: name, of: g, bodies) }
        #expect(g.key(of: room, on: "Erin") != nil, "Erin never got the room's key")
        let unanswered = await g.cloud.everySentPacket.values.filter { $0.receipts.isEmpty }
        #expect(unanswered.isEmpty, "\(unanswered.count) packets were never collected")
    }

    @Test("A message sent at any point of a round is on every phone once", arguments: callsInBobsRound)
    func aMessageSentMidRoundArrivesOnce(call: Int) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])
        let people = ["Alice", "Bob", "Carol", "Dave", "Erin"]
        for name in people where name != "Bob" { try await g[name].send("from \(name)", to: room) }
        await g.takeTurns("Alice", "Carol", "Dave", "Erin")

        let bob = g["Bob"]
        await g.door("Bob").before(call: call) {
            await Task { @MainActor in try? await bob.send("from Bob", to: room) }.value
        }
        await g.takeTurns("Bob")
        await g.door("Bob").forgetSteps()
        try #require(g.shows("from Bob", in: room, on: "Bob"), "Bob's round has fewer than \(call) calls")
        try await g.settle()

        g.sameRoom(room, on: people)
        for name in people { everyMessageOnce(in: room, on: name, of: g, people.map { "from \($0)" }) }
    }

    @Test("Alice's app ends between writing a removal and handing out the new key, and everybody who stays gets it",
        arguments: callsInAlicesRoundAfterARemoval)
    func anAppEndingAfterARemovalStillHandsOutTheKey(call: Int) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])
        let erinHeld = try #require(g["Erin"].chains[room]?.knownEpochs.count)

        try await g["Alice"].remove(g.id("Erin"), from: room)
        let ended = await g.endProcess(of: "Alice", atCall: call)
        await g.takeTurns("Alice")
        #expect(await ended.iCloud != nil, "Alice's round has fewer than \(call) calls, so her app never ended")
        await g.relaunch("Alice")
        try await g.settle()
        try await g["Alice"].send("after Erin", to: room)
        try await g.settle()

        try expectTheKeyReachedEveryoneWhoStays(g, room, erinHeld: erinHeld, call: call)
    }

    @Test(
        "A write that fails just after a removal leaves the new key still owed",
        arguments: callsInAlicesRoundAfterARemoval)
    func aFailedWriteAfterARemovalLeavesTheKeyOwed(call: Int) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])
        let erinHeld = try #require(g["Erin"].chains[room]?.knownEpochs.count)

        try await g["Alice"].remove(g.id("Erin"), from: room)
        let before = await g.door("Alice").calls.count
        await g.door("Alice").fail(call: call)
        await g.takeTurns("Alice")
        #expect(await g.door("Alice").calls.count - before >= call, "Alice's round ended before the failed call")
        await g.door("Alice").forgetSteps()
        await g.takeTurns("Alice")
        try await g.settle()
        try await g["Alice"].send("after Erin", to: room)
        try await g.settle()

        try expectTheKeyReachedEveryoneWhoStays(g, room, erinHeld: erinHeld, call: call)
    }

    private func expectTheKeyReachedEveryoneWhoStays(
        _ g: Gathering, _ room: RoomID, erinHeld: Int, call: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        for name in ["Bob", "Carol", "Dave"] {
            #expect(
                g.key(of: room, on: name) == g.key(of: room, on: "Alice"),
                "\(name) does not hold Alice's new key, cut at call \(call)", sourceLocation: sourceLocation)
            #expect(
                g.shows("after Erin", in: room, on: name), "\(name) cannot read Alice, cut at call \(call)",
                sourceLocation: sourceLocation)
        }
        #expect(
            g["Erin"].chains[room]?.knownEpochs.count == erinHeld, "Erin was handed a key after her removal",
            sourceLocation: sourceLocation)
        #expect(!g.shows("after Erin", in: room, on: "Erin"), "Erin read Alice", sourceLocation: sourceLocation)
        #expect(
            g["Erin"].roster(of: room).removal(of: g.id("Erin")) != nil, "Erin was never told",
            sourceLocation: sourceLocation)
        #expect(g["Alice"].unsentEntries().isEmpty, "Alice shows something unsent", sourceLocation: sourceLocation)
        #expect(
            (try? g["Alice"].grantsOwed().isEmpty) == true, "Alice still owes a key", sourceLocation: sourceLocation)
    }
}
