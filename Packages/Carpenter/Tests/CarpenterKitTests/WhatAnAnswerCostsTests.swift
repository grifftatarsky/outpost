@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("What a repair answer writes is what it is charged", .serialized)
struct WhatAnAnswerCostsTests {
    private func randomID() -> Data { Data((0..<32).map { _ in UInt8.random(in: 0...255) }) }

    @Test("An answer naming back every span a request made up costs the asker's allowance what it wrote")
    func anAnswerIsChargedWhatItWrites() async throws {
        let t = try await RoomOfThree.make()
        let authors = [t.aliceID, t.carolID, t.samID]
        let madeUp = (0..<RepairRequest.mostGaps).map { _ in
            FeedGap(
                feed: FeedKey(author: ParticipantID(rawValue: randomID()), device: DeviceID(rawValue: randomID())),
                spans: [SequenceSpan(1, 1), SequenceSpan(3, 3), SequenceSpan(5, 5), SequenceSpan(7, 7)])
        }
        let request = RepairRequest(
            authors: authors, heads: t.carol.replica.heads(of: Set(authors)), gaps: madeUp, room: t.room)
        let peer = try #require(t.sam.peers().first { $0.them == t.carolID })
        let packet = try SyncEngine.pack(
            [], for: [peer], certificates: [], window: SyncSession.window(at: t.sam.clock.now), requests: [request])
        try await t.mailbox.put(packet, to: t.carolID, in: try #require(t.sam.pairs()))

        let before = Set(await t.mailbox.writtenPackets)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        let sent = await t.mailbox.everySentPacket
        let answers = await t.mailbox.writtenPackets.filter { !before.contains($0) && sent[$0]?.to == t.samID }
        let written = await t.mailbox.storedCiphertextBytes(of: answers)
        let charged = t.carol.persisted.repairSpend[t.samID]?.bytes ?? 0

        #expect(!answers.isEmpty, "precondition: Carol answered")
        #expect(
            written <= charged,
            "one answer wrote \(written) bytes to Carol's iCloud and charged Sam's daily allowance \(charged)")
    }
}
