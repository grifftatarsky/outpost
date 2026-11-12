@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "What a removed device writes counts nowhere", .serialized, .timeLimit(.minutes(10)),
    .tags(.membership, .manyDevices))
struct WhatARemovedDeviceWritesCountsNowhereTests {
    struct Hearing: CustomTestStringConvertible, Sendable {
        let bobHearsFirst: Bool
        let carolHearsFirst: Bool
        let run: Int

        var testDescription: String {
            "Bob hears \(bobHearsFirst ? "first" : "last"), Carol \(carolHearsFirst ? "first" : "last"), run \(run)"
        }

        static let all = [false, true].flatMap { bob in
            [false, true].flatMap { carol in
                (0..<10).map { Hearing(bobHearsFirst: bob, carolHearsFirst: carol, run: $0) }
            }
        }
    }

    @Test(
        "A phone removed but still signed in, running a modified app, changes nothing for anybody",
        arguments: Hearing.all)
    func aRemovedPhoneRunningAModifiedAppChangesNothing(hearing: Hearing) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol"])
        try await g.secondDevice("Alice's tablet", of: "Alice")
        try await g.secondDevice("Alice's old phone", of: "Alice")
        let old = "Alice's old phone"
        let oldKeys = try #require(g[old].enrolment)
        let oldHeld = try #require(g[old].chains[room])
        g.mailboxOnly(old)
        g.away(old)

        try await g["Alice"].send("before the removal", to: room)
        await g.takeTurns("Alice")
        try await g["Alice"].revoke(g.device(old))
        try await g.quiesce()
        let keyAtTheRemoval = try #require(g.key(of: room, on: "Alice"))
        let first = (hearing.bobHearsFirst ? ["Bob"] : []) + (hearing.carolHearsFirst ? ["Carol"] : [])
        let last = ["Bob", "Carol"].filter { !first.contains($0) }
        for friend in last { await g.door("Alice").cannotReach(g.id(friend)) }
        await g.takeTurns(["Alice"] + first)
        try await g["Alice"].send("kept waiting", to: room)
        await g.takeTurns("Alice")

        g.back(old)
        try await g[old].send("from the old phone", to: room)
        try await g[old].advanceEpoch(of: room)
        let oldPhonesKey = g.key(of: room, on: old)
        let oldHeldAfter = try #require(g[old].chains[room])
        let fresh = DeviceKeys.generate()
        let approval = AuthorityEvent.added(
            try DeviceCertificate.issue(
                for: fresh, by: oldKeys.identity, at: TestSession.now.addingTimeInterval(-7 * 86_400),
                approvedBy: oldKeys.device))
        let record = try approval.record(sealedFor: oldKeys.identity, by: oldKeys.device.id)
        try await g.relay(of: "Alice").place(record.name, record.sealed)
        let packetsBefore = await g.cloud.writtenPackets
        await g.takeTurns(old)
        let sent = await g.cloud.everySentPacket
        let written = await g.cloud.writtenPackets.filter { !packetsBefore.contains($0) }
        var pair: (older: PacketID, newest: PacketID)?
        for id in packetsBefore where sent[id] != nil && pair == nil {
            guard await g.cloud.sender(of: id) == g.id("Alice") else { continue }
            if let newest = written.last(where: { sent[$0]?.to == sent[id]?.to }) { pair = (id, newest) }
        }
        let (rewritten, newest) = try #require(
            pair, "precondition: the old phone wrote to a friend who still has an older packet of Alice's waiting")
        let stored = await g.cloud.storedRecords
        let fields = try #require(stored.first { $0.name == newest.rawValue.uuidString }?.fields)
        await g.cloud.tamper(packet: rewritten) { $0 = fields }
        g.away(old)
        await g.takeTurns(last)
        await g.door("Alice").reachesEveryone()
        try await g.settle()

        let everyone = ["Alice", "Alice's tablet", "Bob", "Carol"]
        for name in everyone { try await g[name].send("from \(name)", to: room) }
        try await g.settle()

        let fingerprints = "removal's key \(keyAtTheRemoval.prefix(4).map { String($0) }), "
            + "old phone's key \(oldPhonesKey?.prefix(4).map { String($0) } ?? [])"
        for name in everyone {
            #expect(!g.shows("from the old phone", in: room, on: name), "\(name) shows the removed phone's message")
            #expect(
                g.devices(of: "Alice", seenBy: name).count == 2, "\(name) does not list exactly Alice's two devices")
            let body = "from \(name)"
            #expect(!g.shows(body, in: room, on: old), "the removed phone read \(name)'s message")
            let entry = try #require(g.entry(saying: body, in: room, on: name))
            #expect(entry.opened(using: oldHeld) == nil, "the old phone's keys open \(name)'s message: \(fingerprints)")
        }
        g.sameRoom(room, on: everyone)
        g.back(old)
        await g.takeTurns(old)
        let oldHeldAtTheEnd = try #require(g[old].chains[room])
        let aFriendWasBehindTheOther = hearing.bobHearsFirst != hearing.carolHearsFirst
        for name in everyone {
            if !aFriendWasBehindTheOther {
                #expect(
                    g.key(of: room, on: name) == keyAtTheRemoval, "\(name) writes under another key: \(fingerprints)")
            }
            let entry = try #require(g.entry(saying: "from \(name)", in: room, on: name))
            #expect(
                entry.opened(using: oldHeldAfter) == nil,
                "the key the removed phone made opens \(name)'s message: \(fingerprints)")
            #expect(
                entry.opened(using: oldHeldAtTheEnd) == nil,
                "a key the removed phone was handed opens \(name)'s message: \(fingerprints)")
        }

        g.find(old).mailboxOnly = false
        await g.takeTurns(old)
        #expect(g[old].state == .removed, "the removed phone, given a full turn, did not erase itself")
    }

    private static func isAuthority(_ name: SiblingRecord.Name) -> Bool {
        if case .authority = name.kind { true } else { false }
    }

    @Test(
        "Two of Alice's devices remove each other at once, and everybody keeps the one whose removal was stored first",
        arguments: ["Alice", "Alice's tablet"])
    func twoDevicesRemovingEachOtherLeaveTheFirstStanding(winner: String) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave"])
        try await g.secondDevice("Alice's tablet", of: "Alice")
        try await g.secondDevice("Alice's laptop", of: "Alice")
        let loser = winner == "Alice" ? "Alice's tablet" : "Alice"
        let (winnerID, loserID, laptopID) = (g.device(winner), g.device(loser), g.device("Alice's laptop"))

        g.away("Dave")
        g.clock(loser).advance(by: -3_600)
        try await g[winner].revoke(loserID)
        try await g.quiesce()
        let authorityBefore = await g.relay(of: "Alice").names(from: loserID).count(where: Self.isAuthority)
        do {
            try await g[loser].revoke(winnerID)
        } catch AppSessionError.keyNotRotated {}
        try await g.quiesce()
        let authorityAfter = await g.relay(of: "Alice").names(from: loserID).count(where: Self.isAuthority)
        try #require(authorityAfter > authorityBefore, "precondition: the loser's removal was stored too")
        await g.door(winner).cannotReach(g.id("Dave"))
        await g.takeTurns(winner)
        await g.door(winner).reachesEveryone()
        try await g.settle()
        g.back("Dave")
        try await g.settle()

        let survivors: Set<DeviceID> = [winnerID, laptopID]
        #expect(g.devices(of: "Alice", seenBy: "Alice's laptop") == survivors, "Alice's laptop kept the wrong device")
        #expect(g[loser].state == .removed, "the device removed first did not erase itself")
        try await g[winner].send("still here", to: room)
        try await g.settle()
        #expect(g.shows("still here", in: room, on: "Alice's laptop"))

        for name in ["Bob", "Carol", "Dave"] {
            #expect(
                g.devices(of: "Alice", seenBy: name) == survivors,
                "\(name) does not keep the device whose removal iCloud stored first")
            #expect(g.shows("still here", in: room, on: name), "\(name) cannot read the surviving device")
        }
    }
}
