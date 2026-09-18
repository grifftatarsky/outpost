import CarpenterCloudKit
import CarpenterKit
import CloudKit
import Foundation
import Testing

@Suite("Every field written to a record is a field the scan asks for")
struct ScannedFieldsTests {
    private static func tag() -> RecipientTag {
        RecipientTag(rawValue: Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }

    @Test("A packet's fields are all named in the scan")
    func everyPacketFieldIsScanned() {
        let mine = Self.tag()
        let written = PacketWire.fields(
            of: SyncPacket(
                wraps: [mine: Data(count: 32)],
                ciphertext: Data(count: 64),
                grants: [mine: [Data(count: 32)]]))

        let asked = Set(CloudKitMailbox.scannedFields)
        for field in written.keys {
            #expect(
                asked.contains(field),
                """
                `\(field)` is written to the record and left off \
                `CloudKitMailbox.scannedFields`, so every fetch returns it as nil. That is not an \
                error anywhere — it is a record that reads as empty, which is how "found 0 offer(s)" \
                stood for an afternoon beside a fresh offer, and how `grants` was silently stripped. \
                This is checked against the mapping rather than a second list so the two cannot \
                drift.
                """)
        }
    }

    @Test("An attachment's routing fields are named, and its blob deliberately is not")
    func everyAttachmentRoutingFieldIsScanned() {
        let written = AttachmentWire.fields(
            of: OutgoingAttachment(
                id: AttachmentID(), ciphertext: Data(count: 1_024), recipients: [Self.tag()]))

        let asked = Set(CloudKitMailbox.scannedFields)
        for field in written.keys where field != AttachmentWire.blob {
            #expect(
                asked.contains(field),
                "`\(field)` routes an attachment and the scan does not ask for it")
        }
        #expect(
            !asked.contains(AttachmentWire.blob),
            """
            The scan asks for the photo blob, so every routing read drags every photo in the zone \
            down with it. The blob is fetched by `download`, on its own, on purpose.
            """)
    }
}
