import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("The order a file mailbox hands packets back in")
struct FileMailboxOrderTests {
    private func tag(_ byte: UInt8) -> RecipientTag {
        RecipientTag(rawValue: Data(repeating: byte, count: 16))
    }

    @Test("Packets come back in the order they were written, even after the reader has signed for one")
    func writeOrderSurvivesAnAcknowledgement() async throws {
        let directory = TestScratch.root.appending(path: "carpenter-order-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = FileMailbox(directory: directory)
        let (toBob, asBob) = try peers(Identity.generate(), Identity.generate())
        let (alice, bob) = try await link(toBob, asBob, through: mailbox)
        let tag = toBob.outgoingTag(window: 1)

        var written: [PacketID] = []
        for _ in 0..<20 {
            let packet = SyncPacket(wraps: [tag: Data([1])], ciphertext: Data([3]))
            try await mailbox.put(packet, to: toBob.them, in: alice)
            written.append(packet.id)
        }
        try await mailbox.acknowledge(written[0], from: toBob.me, with: SealedReceipt(tag: tag, sealed: Data([9])), in: bob)

        #expect(
            try await mailbox.fetch(from: toBob.me, for: [tag], in: bob).map(\.id) == written,
            """
            The packets came back out of the order they were written. A delivery's `notifyWalls` \
            is taken from the last packet, so an arbitrary order applies an older wish.
            """)
    }
}
