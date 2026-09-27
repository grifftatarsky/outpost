import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("The order a file mailbox hands packets back in")
struct FileMailboxOrderTests {
    private func tag(_ byte: UInt8) -> RecipientTag {
        RecipientTag(rawValue: Data(repeating: byte, count: 16))
    }

    @Test("Packets come back in the order they were written, even after one recipient has taken one")
    func writeOrderSurvivesAnAcknowledgement() async throws {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-order-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = FileMailbox(directory: directory)
        let (bob, carol) = (tag(1), tag(2))

        var written: [PacketID] = []
        for _ in 0..<20 {
            let packet = SyncPacket(wraps: [bob: Data([1]), carol: Data([2])], ciphertext: Data([3]))
            try await mailbox.put(packet)
            written.append(packet.id)
        }
        try await mailbox.acknowledge(written[0], with: SealedReceipt(tag: carol, sealed: Data([9])))

        #expect(
            try await mailbox.fetch(for: [bob]).map(\.id) == written,
            """
            The packets came back out of the order they were written. A delivery's `notifyWalls` \
            is taken from the last packet, so an arbitrary order applies an older wish.
            """)
    }
}
