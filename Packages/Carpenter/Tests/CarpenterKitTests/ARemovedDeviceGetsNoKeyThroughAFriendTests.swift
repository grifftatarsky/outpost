@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "A removed device gets no key through a friend", .serialized, .timeLimit(.minutes(10)),
    .tags(.membership, .manyDevices))
struct ARemovedDeviceGetsNoKeyThroughAFriendTests {
    @Test(
        "A key a friend makes before hearing Bob removed his tablet stops opening on the tablet",
        arguments: ["Alice", "Carol", "Dave"])
    func aKeyMadeEarlyStopsOpeningOnTheRemovedDevice(late: String) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])
        try await g.secondDevice("Bob's tablet", of: "Bob")
        let friends = ["Alice", "Carol", "Dave"]

        g.mailboxOnly("Bob's tablet")
        try await g["Bob"].revoke(g.device("Bob's tablet"))
        await g.door("Bob").cannotReach(g.id(late))
        await g.takeTurns("Bob")
        await g.takeTurns(friends.filter { $0 != late })
        let packetsBefore = Set(await g.cloud.writtenPackets)
        try #require(
            g.devices(of: "Bob", seenBy: late).count == 2, "precondition: \(late) has not heard of the removal")
        let keyBefore = g.key(of: room, on: late)
        try await g[late].remove(g.id("Erin"), from: room)
        let lateFriendsKey = try #require(g.key(of: room, on: late))
        try #require(lateFriendsKey != keyBefore, "precondition: \(late)'s removal of Erin made a new key")
        await g.takeTurns(late)
        var grantsToBob = 0
        for id in await g.cloud.writtenPackets where !packetsBefore.contains(id) {
            if await g.cloud.everySentPacket[id]?.to == g.id("Bob") { grantsToBob += await g.cloud.grantCount(in: id) }
        }
        try #require(grantsToBob > 0, "precondition: \(late) passed Bob a key while still listing the tablet")
        try #require(
            g.devices(of: "Bob", seenBy: late).count == 2, "precondition: \(late) heard of the removal too soon")
        await g.takeTurns("Bob's tablet")
        let tabletHeld = try #require(g["Bob's tablet"].chains[room])
        await g.door("Bob").reachesEveryone()
        try await g.settle()

        for friend in friends { try await g[friend].send("from \(friend)", to: room) }
        try await g.settle()

        g.sameRoom(room, on: friends + ["Bob"])
        for friend in friends {
            let body = "from \(friend)"
            #expect(g.shows(body, in: room, on: "Bob"), "Bob's phone never read \(friend)'s message")
            #expect(!g.shows(body, in: room, on: "Bob's tablet"), "the removed tablet read \(friend)'s message")
        }
        #expect(g.key(of: room, on: "Alice") != lateFriendsKey, "the room is still written under \(late)'s key")
        for friend in friends {
            let entry = try #require(g.entry(saying: "from \(friend)", in: room, on: friend))
            #expect(entry.opened(using: tabletHeld) == nil, "the tablet's old keys open \(friend)'s message")
        }
    }

    @Test("A key a friend passes on to Bob's tablet before hearing it was removed does not stay the room's key")
    func aKeyPassedOnEarlyIsReplaced() async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave"])
        try await g.secondDevice("Bob's tablet", of: "Bob")
        let friends = ["Alice", "Carol", "Dave"]

        g.mailboxOnly("Bob's tablet")
        try await g["Bob"].revoke(g.device("Bob's tablet"))
        await g.door("Bob").cannotReach(g.id("Dave"))
        await g.takeTurns("Bob", "Alice", "Carol")
        let bobsKey = try #require(g.key(of: room, on: "Bob"))
        try #require(g.key(of: room, on: "Alice") == bobsKey, "precondition: Alice took the key Bob made")
        let packetsBefore = Set(await g.cloud.writtenPackets)
        await g.takeTurns("Dave")
        try #require(g.key(of: room, on: "Dave") == bobsKey, "precondition: a friend passed Dave the key Bob made")
        try #require(g.devices(of: "Bob", seenBy: "Dave").count == 2, "precondition: Dave has not heard of the removal")
        var grantsToBob = 0
        for id in await g.cloud.writtenPackets where !packetsBefore.contains(id) {
            if await g.cloud.everySentPacket[id]?.to == g.id("Bob") { grantsToBob += await g.cloud.grantCount(in: id) }
        }
        try #require(grantsToBob > 0, "precondition: Dave passed Bob's key on while still listing the tablet")
        await g.takeTurns("Bob's tablet")
        let tabletHeld = try #require(g["Bob's tablet"].chains[room])
        await g.door("Bob").reachesEveryone()
        try await g.settle()

        for friend in friends { try await g[friend].send("from \(friend)", to: room) }
        try await g.settle()

        g.sameRoom(room, on: friends + ["Bob"])
        #expect(g.key(of: room, on: "Alice") != bobsKey, "the room is still written under a key the tablet was sent")
        for friend in friends {
            let entry = try #require(g.entry(saying: "from \(friend)", in: room, on: friend))
            #expect(entry.opened(using: tabletHeld) == nil, "the tablet's keys open \(friend)'s message")
            #expect(!g.shows("from \(friend)", in: room, on: "Bob's tablet"), "the removed tablet read \(friend)")
        }
    }

    @Test("Removing a device gives the room one new key, not one from every friend who hears of it")
    func removingADeviceMakesOneKey() async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave"])
        try await g.secondDevice("Bob's tablet", of: "Bob")
        let people = ["Alice", "Bob", "Carol", "Dave"]

        g.away("Bob's tablet")
        try await g["Bob"].revoke(g.device("Bob's tablet"))
        try await g.settle()

        for name in people {
            let chain = try #require(g[name].chains[room])
            let newest = try #require(chain.highestKnownEpoch)
            #expect(chain.heldSecrets(at: newest).count == 1, "\(name) holds rival keys after one device was removed")
            #expect(g.devices(of: "Bob", seenBy: name).count == 1, "\(name) still lists Bob's tablet")
        }
        g.sameRoom(room, on: people)
    }

    @Test("A friend's device removal that a phone collects reaches that member's tablet through its device mail")
    func aFriendsDeviceRemovalReachesTheMembersOtherDevice() async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol")
        _ = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol"])
        try await g.secondDevice("Bob's tablet", of: "Bob")
        try await g.secondDevice("Alice's tablet", of: "Alice")
        try await g.settle()
        try #require(
            g.devices(of: "Bob", seenBy: "Alice's tablet").count == 2,
            "precondition: Alice's tablet lists both of Bob's devices")

        g.away("Bob's tablet")
        await g.door("Alice's tablet").cannotCollect(from: g.id("Bob"))
        try await g["Bob"].revoke(g.device("Bob's tablet"))
        await g.takeTurns("Bob", "Alice")
        try #require(
            g.devices(of: "Bob", seenBy: "Alice").count == 1, "precondition: Alice's phone heard of the removal")
        await g.takeTurns("Alice's tablet")

        #expect(
            g.devices(of: "Bob", seenBy: "Alice's tablet").count == 1,
            "Alice's tablet never heard that Bob removed his tablet, and would go on sealing keys to it")
    }

    @Test("A friend a round behind on a member's new phone still gets the key to that phone")
    func aFriendBehindStillReachesTheNewPhone() async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave"])

        g.away("Alice")
        try await g.secondDevice("Bob's new phone", of: "Bob")
        try await g["Bob's new phone"].revoke(g.device("Bob"))
        try await g.quiesce()
        await g.takeTurns("Bob's new phone", "Bob", "Carol", "Dave")
        g.back("Alice")
        for friend in ["Bob", "Carol", "Dave"] { await g.door("Alice").cannotCollect(from: g.id(friend)) }
        await g.takeTurns("Alice")
        try #require(
            g.devices(of: "Bob", seenBy: "Alice") == [g.device("Bob")],
            "precondition: Alice lists only Bob's old phone")
        try await g["Alice"].advanceEpoch(of: room)
        try await g["Alice"].send("for the new phone", to: room)
        await g.takeTurns("Alice")
        let alicesKey = try #require(g.chainHoldingOnlyTheWritingKey(of: room, on: "Alice"))
        let entry = try #require(g.entry(saying: "for the new phone", in: room, on: "Alice"))
        try #require(entry.opened(using: alicesKey) != nil, "precondition: Alice sealed her message under her new key")
        try #require(
            g["Bob's new phone"].chains[room].map { entry.opened(using: $0) == nil } ?? true,
            "precondition: Bob's new phone did not already hold the key Alice made")
        await g.door("Alice").collectsFromEveryone()
        try await g.settle()

        #expect(g.devices(of: "Bob", seenBy: "Alice").count == 1, "Alice still lists Bob's old phone")
        #expect(g.shows("for the new phone", in: room, on: "Bob's new phone"), "Bob's new phone never read Alice")
        g.sameRoom(room, on: ["Alice", "Bob's new phone", "Carol", "Dave"])
    }
}
