@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Blocking somebody you share a room with alone, and unblocking them", .serialized, .tags(.sync))
struct BlockingInARoomOfTwoTests {
    @MainActor
    private struct Two {
        let mailbox: InMemoryMailbox
        let ada: AppSession
        let bea: AppSession
        let room: RoomID

        var adaID: ParticipantID { ada.enrolment!.identity.id }
        var beaID: ParticipantID { bea.enrolment!.identity.id }
        var adas: String { LocalPairStore.account(of: adaID) }
        var beas: String { LocalPairStore.account(of: beaID) }

        func settle(rounds: Int = 4) async throws {
            for _ in 0..<rounds {
                try await ada.sync(through: mailbox, media: mailbox)
                try await bea.sync(through: mailbox, media: mailbox)
            }
        }

        func heard(_ session: AppSession, _ body: String) -> Bool {
            session.messages(in: room).contains { $0.body == body }
        }
    }

    private func two() async throws -> Two {
        let mailbox = InMemoryMailbox()
        let (ada, bea) = (TestSession.make(), TestSession.make())
        for (session, name) in [(ada, "Ada"), (bea, "Bea")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        let room = try await ada.createRoom(named: "Blocks")
        try await join(bea, into: room, of: ada, through: mailbox)
        let two = Two(mailbox: mailbox, ada: ada, bea: bea, room: room)
        try await two.settle()
        try #require(ada.roster(of: room).members.count == 2, "precondition: two members")
        try await ada.send("before, from Ada", to: room)
        try await bea.send("before, from Bea", to: room)
        try await two.settle()
        try #require(two.heard(bea, "before, from Ada") && two.heard(ada, "before, from Bea"), "precondition: both ways")
        return two
    }

    @Test("After Bea blocks Ada and unblocks her, what each writes reaches the other")
    func messagesCrossBothWaysAfterAnUnblock() async throws {
        let t = try await two()
        await t.bea.block(t.adaID)
        try await t.settle()
        await t.bea.unblock(t.adaID)
        try await t.settle()

        try await t.bea.send("after, from Bea", to: t.room)
        try await t.ada.send("after, from Ada", to: t.room)
        try await t.settle()
        #expect(t.heard(t.ada, "after, from Bea"), "what the person who blocked wrote after the unblock never arrived")
        #expect(t.heard(t.bea, "after, from Ada"), "what the person who was blocked wrote after the unblock never arrived")
    }

    @Test("Unblocking opens the same space again, so the link Ada already holds still leads to it")
    func unblockingReopensTheSameSpace() async throws {
        let t = try await two()
        let before = try #require(t.ada.link(for: t.beaID), "precondition: Ada holds Bea's link")
        await t.bea.block(t.adaID)
        try await t.settle()
        #expect(!(await t.mailbox.reads(t.beaID, in: try t.ada.currentPairs())), "Ada still read the space Bea closed to her")
        await t.bea.unblock(t.adaID)
        try await t.settle()
        #expect(t.ada.link(for: t.beaID) == before, "unblocking moved Bea to a space Ada has no way to hear of")
        #expect(t.ada.pairsJoined.contains(t.beaID), "Ada never joined Bea's space again")
    }

    @Test("While Bea blocks Ada, nothing Ada writes rings Bea's phone")
    func aBlockedPersonCannotRingYou() async throws {
        let t = try await two()
        await t.bea.block(t.adaID)
        try await t.settle()

        let before = await t.mailbox.rings.count
        for word in ["one", "two", "three"] {
            try await t.ada.send("blocked, \(word)", to: t.room)
            try await t.ada.sync(through: t.mailbox, media: t.mailbox)
        }
        let rung = await t.mailbox.rings.dropFirst(before).filter { $0.from == t.adaID }
        try #require(!rung.isEmpty, "precondition: Ada's app rang her space for Bea")
        #expect(rung.allSatisfy { !$0.reached.contains(t.beas) }, "a ring from somebody blocked reached the account that blocked them")
    }

    @Test("While Bea blocks Ada, Ada reads nothing Bea writes, and her app cannot read its way back in")
    func aBlockedPersonReadsNothingNew() async throws {
        let t = try await two()
        await t.bea.block(t.adaID)
        try await t.settle()
        try await t.bea.send("while blocked, from Bea", to: t.room)
        try await t.settle()
        #expect(!t.heard(t.ada, "while blocked, from Bea"))

        let adas = try t.ada.currentPairs()
        let link = try #require(t.ada.link(for: t.beaID), "precondition: Ada holds Bea's link")
        #expect(try await t.mailbox.join(link, of: t.beaID, in: adas) != .joined, "Ada put herself back on Bea's space")
        let tags = SyncSession.recentTags(for: try #require(t.ada.peers().first { $0.them == t.beaID }), at: TestSession.now)
        #expect(try await t.mailbox.fetch(from: t.beaID, for: tags, in: adas).isEmpty, "Ada read Bea's space while blocked")
    }

    @Test("What Ada wrote while Bea blocked her arrives once Bea unblocks her")
    func whatWasWrittenDuringTheBlockArrivesAfter() async throws {
        let t = try await two()
        await t.bea.block(t.adaID)
        try await t.settle()
        try await t.ada.send("while blocked, from Ada", to: t.room)
        try await t.settle()
        await t.bea.unblock(t.adaID)
        try await t.settle()
        #expect(t.heard(t.bea, "while blocked, from Ada"), "what was held during the block never arrived")
    }

    @Test("Leaving a contact's space takes you off it, as iCloud does, and only its owner can name you again")
    func leavingNeedsTheOwnerToNameYouAgain() async throws {
        let t = try await two()
        let link = try #require(t.bea.link(for: t.adaID), "precondition: Bea holds Ada's link")
        let beas = try t.bea.currentPairs()
        await t.mailbox.leave(t.adaID, in: beas)
        #expect(await t.mailbox.join(link, of: t.adaID, in: beas) == .notYetNamed, "a reader who left joined again by herself")
        try await t.ada.sync(through: t.mailbox, media: t.mailbox)
        #expect(await t.mailbox.join(link, of: t.adaID, in: beas) == .joined, "the owner's next round did not name her again")
    }

    @Test("Blocking and unblocking ten times in a row leaves both ways open")
    func tenBlocksInARow() async throws {
        let t = try await two()
        for round in 1...10 {
            await t.bea.block(t.adaID)
            try await t.settle(rounds: 2)
            await t.bea.unblock(t.adaID)
            try await t.settle(rounds: 3)
            try await t.bea.send("Bea, round \(round)", to: t.room)
            try await t.ada.send("Ada, round \(round)", to: t.room)
            try await t.settle(rounds: 3)
            #expect(t.heard(t.ada, "Bea, round \(round)"), "round \(round): Bea's message did not reach Ada")
            #expect(t.heard(t.bea, "Ada, round \(round)"), "round \(round): Ada's message did not reach Bea")
        }
    }
}
