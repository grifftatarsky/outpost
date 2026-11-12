@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "A member with no room in iCloud reads everything, is told why, and catches up", .serialized,
    .timeLimit(.minutes(10)), .tags(.sync, .manyDevices))
struct AMemberWithNoRoomInICloudCatchesUpTests {
    private static let senders = ["Alice", "Bob", "Carol"]
    private static let everyone = senders + ["Dave"]

    private func lanternsWithEveryoneWriting(
        whileDaveIs refusal: MailboxFailure, deletesRefused: Bool, daveFirst: Bool
    ) async throws -> (Gathering, RoomID) {
        let g = try await Gathering.of(Self.everyone)
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave"])
        await g.door("Dave").refuseEverySave(refusal, deletesToo: deletesRefused)
        for sender in Self.senders { try await g[sender].send("from \(sender)", to: room) }
        try await g["Dave"].send("from Dave", to: room)
        let order = daveFirst ? ["Dave"] + Self.senders : Self.senders + ["Dave"]
        for _ in 0..<3 { await g.takeTurns(order) }
        return (g, room)
    }

    private func expectNothingMovedEarly(in g: Gathering, room: RoomID) async {
        for sender in Self.senders {
            let delivery = g[sender].messages(in: room).first { $0.body == "from \(sender)" }?.delivery
            #expect(
                delivery?.isCollected == false,
                "\(sender) sees their message collected before Dave could sign for it: \(String(describing: delivery))")
            #expect(
                g[sender].pendingRecipients?.isEmpty == false,
                "\(sender) took back what waits for Dave before he had room")
            #expect(!g.shows("from Dave", in: room, on: sender), "\(sender) read Dave's message, which was never saved")
        }
        let forDave = await g.cloud.everySentPacket.values.filter { $0.to == g.id("Dave") }
        #expect(forDave.count >= Self.senders.count, "only \(forDave.count) packets still wait for Dave")
        #expect(
            forDave.allSatisfy { $0.receipts.isEmpty }, "a receipt from Dave was stored while he could save nothing")
    }

    private func expectCaughtUp(_ g: Gathering, room: RoomID) async {
        g.sameRoom(room, on: Self.everyone)
        for name in Self.everyone {
            for author in Self.everyone {
                let copies = g[name].messages(in: room).count { $0.body == "from \(author)" }
                #expect(copies == 1, "\(name) shows \(author)'s message \(copies) times")
            }
        }
        #expect(g["Dave"].cannotSend == nil, "Dave is still told he cannot send after it went")
        for sender in Self.senders {
            let delivery = g[sender].messages(in: room).first { $0.body == "from \(sender)" }?.delivery
            #expect(delivery?.isCollected == true, "\(sender) never saw Dave collect: \(String(describing: delivery))")
        }
        let forDave = await g.cloud.everySentPacket.values.filter { $0.to == g.id("Dave") }
        #expect(forDave.isEmpty, "\(forDave.count) packets still wait for Dave after he signed for everything")
    }

    @Test(
        "Dave reads every message while iCloud has no room for his, is told why, and catches up when it has",
        arguments: [false, true], [false, true])
    func noRoomInICloud(deletesRefused: Bool, daveFirst: Bool) async throws {
        let (g, room) = try await lanternsWithEveryoneWriting(
            whileDaveIs: .noRoomInICloud, deletesRefused: deletesRefused, daveFirst: daveFirst)

        for sender in Self.senders {
            #expect(g.shows("from \(sender)", in: room, on: "Dave"), "Dave never read \(sender)'s message")
        }
        #expect(g["Dave"].cannotSend == .noRoomInICloud, "Dave is not told his iCloud is full")
        await expectNothingMovedEarly(in: g, room: room)

        await g.door("Dave").relent()
        try await g.settle()

        await expectCaughtUp(g, room: room)
    }

    @Test(
        "Dave signed out of iCloud reads nothing, is told why, and catches up when he signs in",
        arguments: [false, true])
    func signedOut(daveFirst: Bool) async throws {
        let (g, room) = try await lanternsWithEveryoneWriting(
            whileDaveIs: .notSignedIn, deletesRefused: true, daveFirst: daveFirst)

        for sender in Self.senders {
            #expect(!g.shows("from \(sender)", in: room, on: "Dave"), "Dave read \(sender) while signed out")
        }
        #expect(g["Dave"].cannotSend == .notSignedIn, "Dave is not told he is signed out")
        await expectNothingMovedEarly(in: g, room: room)

        await g.door("Dave").relent()
        try await g.settle()

        await expectCaughtUp(g, room: room)
    }
}
