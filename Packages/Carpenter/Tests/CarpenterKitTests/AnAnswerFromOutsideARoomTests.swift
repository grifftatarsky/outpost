@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("An answer from somebody outside a room does not stop a member recovering that room", .serialized)
struct AnAnswerFromOutsideARoomTests {
    private func loseWhatWasJustSent(
        to person: ParticipantID, by sender: AppSession, also others: [AppSession], in t: RoomOfThree
    ) async throws {
        let before = Set(await t.mailbox.writtenPackets)
        try await sender.sync(through: t.mailbox, media: t.mailbox)
        let sent = await t.mailbox.everySentPacket
        for id in await t.mailbox.writtenPackets where !before.contains(id) && sent[id]?.to == person {
            await lose(id, from: t.mailbox, sentBy: [sender] + others)
        }
    }

    @Test("Carol still recovers a Kitchen message after Sam, who is not in the Kitchen, answers her Lanterns repair")
    func anOutsiderDoesNotEndTheSearch() async throws {
        let t = try await RoomOfThree.make()
        let kitchen = try await t.alice.createRoom(named: "Kitchen")
        try await join(t.carol, into: kitchen, of: t.alice, through: t.mailbox)
        try await t.settle()
        try #require(t.carol.roster(of: kitchen).members.contains(t.carolID), "precondition: Carol is in the Kitchen")
        try #require(!t.sam.roster(of: kitchen).members.contains(t.samID), "precondition: Sam is not")

        try await t.alice.send("only for the kitchen", to: kitchen)
        let written = try #require(t.alice.replica.allEntries.last { $0.room == kitchen })
        try await loseWhatWasJustSent(to: t.carolID, by: t.alice, also: [t.carol], in: t)
        try await loseWhatWasJustSent(to: t.carolID, by: t.sam, also: [t.carol], in: t)
        try #require(t.sam.replica.allEntries.contains { $0.hash == written.hash }, "precondition: Sam holds the Kitchen entry")
        try await t.alice.send("then in the lanterns", to: t.room)
        try await t.settle()
        try #require(!t.carol.missingHistory(in: kitchen).isEmpty, "precondition: Carol sees the hole")

        await t.carol.startRepair(in: t.room, asking: t.samID)
        try await t.settle()
        let stillSeen = !t.carol.missingHistory(in: kitchen).isEmpty
        #expect(stillSeen, "one answer from outside the Kitchen made Carol stop seeing a Kitchen hole")

        await t.carol.startRepair(in: kitchen, asking: t.aliceID)
        try await t.settle()
        let recovered = t.carol.messages(in: kitchen).contains { $0.body == "only for the kitchen" }
        #expect(recovered, "Alice, who holds it and shares the Kitchen with Carol, was never asked for it")
    }
}
