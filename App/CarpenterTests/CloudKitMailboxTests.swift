import CarpenterCloudKit
import CarpenterKit
import CloudKit
import Foundation
import Testing

enum LiveCloudKit {
    static let flag = "CARPENTER_CLOUDKIT_TESTS"

    static var isAsked: Bool {
        ProcessInfo.processInfo.environment[flag] == "1"
    }

    static func mailbox() async throws -> CloudKitMailbox {
        let container = CKContainer.default()

        var status = try await container.accountStatus()
        var waited = 0
        while status == .temporarilyUnavailable || status == .couldNotDetermine, waited < 10 {
            try? await Task.sleep(for: .seconds(2))
            waited += 1
            status = try await container.accountStatus()
        }

        guard status == .available else {
            Issue.record(
                """
                \(flag) is set but this device's iCloud account is not usable (\(status)) after \
                \(waited) retr(ies). These tests are the only thing that reads the real wire \
                format; a skip here is a gap, not a pass. temporarilyUnavailable and \
                couldNotDetermine are retried because a simulator reports them for a while after \
                it boots; noAccount means sign in on the device.
                """)
            throw CancellationError()
        }
        let mailbox = CloudKitMailbox(container: container)
        try await mailbox.prepare()
        return mailbox
    }

    static func tag() -> RecipientTag {
        RecipientTag(rawValue: Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }

    static func bytes(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max) })
    }
}

@Suite(
    "The mailbox against a real CloudKit account",
    .enabled(if: LiveCloudKit.isAsked),
    .serialized)
struct CloudKitMailboxTests {
    @Test("A packet comes back exactly as it went")
    func aPacketComesBackExactly() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let mine = LiveCloudKit.tag()
        let other = LiveCloudKit.tag()

        let sent = SyncPacket(
            wraps: [mine: LiveCloudKit.bytes(48), other: LiveCloudKit.bytes(48)],
            ciphertext: LiveCloudKit.bytes(4096),
            grants: [mine: [LiveCloudKit.bytes(32), LiveCloudKit.bytes(32)]])

        try await mailbox.put(sent)
        let back = try await mailbox.fetch(for: [mine])

        let found = try #require(
            back.first { $0.id == sent.id },
            """
            A packet written to a real account did not come back for the tag it was addressed to. \
            Everything in the suite that is not this test talks to an in-memory fake.
            """)
        #expect(found.ciphertext == sent.ciphertext, "the sealed bytes changed on the wire")
        #expect(
            found.wraps == sent.wraps,
            """
            The per-recipient wraps did not survive. A dictionary keyed by recipient holding one \
            value is a failure this app has already had once.
            """)
        #expect(
            found.grants.keys.sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
                == sent.grants.keys.sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) },
            "an address owed keys lost its entry entirely")
        for (tag, owed) in sent.grants {
            #expect(
                Set(found.grants[tag] ?? []) == Set(owed),
                """
                The epoch grants did not survive as a list per address. A round owing one person \
                keys to two rooms used to deliver the last and drop the rest. Compared as a set: \
                the wire does not promise an order for this list, and asserting one made this test \
                fail on 2026-09-13 for a difference that costs nothing.
                """)
        }
        #expect(
            found.contentDigest == sent.contentDigest,
            "a packet nobody touched reads back as altered, so every round would send it again")
        let listed = try #require(try await mailbox.sentPackets()[sent.id])
        #expect(listed.contentDigest == sent.contentDigest, "the outbox listing reads an untouched packet as altered")

        try await mailbox.withdraw(sent.id)
    }

    @Test("Every field the scan names comes back on the record")
    func everyScannedFieldComesBack() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let mine = LiveCloudKit.tag()

        let sent = SyncPacket(
            wraps: [mine: LiveCloudKit.bytes(48)],
            ciphertext: LiveCloudKit.bytes(64),
            grants: [mine: [LiveCloudKit.bytes(32)]])
        try await mailbox.put(sent)

        let found = try #require((try await mailbox.fetch(for: [mine])).first { $0.id == sent.id })
        #expect(
            !found.ciphertext.isEmpty && !found.wraps.isEmpty && !found.grants.isEmpty,
            """
            A field came back empty from a scan that names it. This is the desiredKeys trap: a \
            field left off `CloudKitMailbox.scannedFields` is not an error anywhere, it is a record \
            that looks empty — and it cost an afternoon of "found 0 offer(s)" while a fresh offer \
            stood in the zone.
            """)

        try await mailbox.withdraw(sent.id)
    }

    @Test("A packet is readable the instant it is written, without a query")
    func aPacketIsReadableImmediately() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let mine = LiveCloudKit.tag()

        let sent = SyncPacket(wraps: [mine: LiveCloudKit.bytes(48)], ciphertext: LiveCloudKit.bytes(64))
        try await mailbox.put(sent)

        #expect(
            (try await mailbox.fetch(for: [mine])).contains { $0.id == sent.id },
            """
            Write-then-read did not find the packet. CloudKit's query index is eventually \
            consistent and this app reads the zone's change feed for exactly that reason; if this \
            fails, something has gone back to a query. That cost a week once.
            """)

        try await mailbox.withdraw(sent.id)
    }

    @Test("A photo's bytes survive the wire, and a receipt leaves them where they are")
    func anAttachmentSurvivesTheWire() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let mine = LiveCloudKit.tag()
        let sealed = LiveCloudKit.bytes(300_000)
        let second = LiveCloudKit.tag()
        let attachment = OutgoingAttachment(
            id: AttachmentID(), ciphertext: sealed, recipients: [mine, second])

        try await mailbox.upload(attachment)

        let back = try await mailbox.download(attachment.id, hint: [mine])
        #expect(
            back == sealed,
            """
            A photo's sealed bytes changed between upload and download. Media is its own record \
            type with its own fields, so the packet round trip says nothing about it — and a photo \
            that comes back altered is one that will never open.
            """)
        #expect(
            (try await mailbox.pendingAttachments())[attachment.id]?.recipients == [mine, second],
            "a freshly uploaded attachment did not report who it is for")
        #expect(
            (try await mailbox.sweepableAttachments())[attachment.id] == nil,
            """
            An attachment uploaded seconds ago is already sweepable. The hour exists so the sweep \
            does not delete an upload whose entry has not been integrated yet.
            """)

        let receipt = SealedReceipt(tag: mine, sealed: LiveCloudKit.bytes(120))
        try await mailbox.acknowledge(attachment: attachment.id, with: receipt)
        #expect(
            (try await mailbox.pendingAttachments())[attachment.id]?.receipts == [receipt],
            "a receipt written onto an attachment did not come back from the server")
        #expect(
            try await mailbox.download(attachment.id, hint: [second]) == sealed,
            "signing for a photo took its bytes away; only the sender clears what it sent")

        try await mailbox.delete(attachment: attachment.id)
    }

    @Test("Two receipts written at once both land, and putting a photo back keeps them")
    func receiptsDoNotEraseEachOther() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let first = LiveCloudKit.tag()
        let second = LiveCloudKit.tag()
        let sealed = LiveCloudKit.bytes(120_000)
        let attachment = OutgoingAttachment(
            id: AttachmentID(), ciphertext: sealed, recipients: [first, second])
        try await mailbox.upload(attachment)

        let receipts = [
            SealedReceipt(tag: first, sealed: LiveCloudKit.bytes(96)),
            SealedReceipt(tag: second, sealed: LiveCloudKit.bytes(96)),
        ]
        try await withThrowingTaskGroup(of: Void.self) { group in
            for receipt in receipts {
                group.addTask { try await mailbox.acknowledge(attachment: attachment.id, with: receipt) }
            }
            try await group.waitForAll()
        }
        #expect(
            Set((try await mailbox.pendingAttachments())[attachment.id]?.receipts ?? []) == Set(receipts),
            """
            Two recipients signed for a photo at the same moment and one signature was lost. Each \
            write reads the record and saves it only if nobody changed it since, and retries if \
            somebody did; a lost signature keeps a photo in iCloud until its time runs out.
            """)

        try await mailbox.upload(attachment)
        #expect(
            Set((try await mailbox.pendingAttachments())[attachment.id]?.receipts ?? []) == Set(receipts),
            "putting a photo back over its record dropped the signatures already on it")

        try await mailbox.delete(attachment: attachment.id)
        #expect(
            (try await mailbox.pendingAttachments())[attachment.id] == nil,
            "the sender cleared a photo and it is still in the outbox")
    }

    @Test("Packets come back in the order they were written")
    func packetsComeBackInWriteOrder() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let mine = LiveCloudKit.tag()

        var written: [PacketID] = []
        for _ in 0..<4 {
            let packet = SyncPacket(
                wraps: [mine: LiveCloudKit.bytes(48)], ciphertext: LiveCloudKit.bytes(64))
            try await mailbox.put(packet)
            written.append(packet.id)
        }

        let back = try await mailbox.fetch(for: [mine]).map(\.id)
        let places = try written.map { try #require(back.firstIndex(of: $0)) }

        #expect(
            places == places.sorted(),
            """
            A zone's records came back out of order. `recordZoneChanges` hands them over in \
            `modificationResultsByID`, which is a Dictionary, so iterating it is not an order at \
            all — and the in-memory fake replays packets in the order they were written, so every \
            test in the suite sees an order the real mailbox never promised. What rides on it: a \
            delivery's `notifyWalls` is the one field `integrate` takes from the last packet \
            rather than accumulating, so an arbitrary order silently applies a peer's *older* wish \
            about their wall bell, and the peer only re-sends the list when it changes.
            """)

        for id in written { try await mailbox.withdraw(id) }
    }

    @Test("A packet one recipient has taken keeps its place for the others")
    func aPartlyAcknowledgedPacketKeepsItsPlace() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let bob = LiveCloudKit.tag()
        let carol = LiveCloudKit.tag()

        var written: [PacketID] = []
        for _ in 0..<3 {
            let packet = SyncPacket(
                wraps: [bob: LiveCloudKit.bytes(48), carol: LiveCloudKit.bytes(48)],
                ciphertext: LiveCloudKit.bytes(64))
            try await mailbox.put(packet)
            written.append(packet.id)
        }
        try await mailbox.acknowledge(written[0], with: SealedReceipt(tag: carol, sealed: LiveCloudKit.bytes(40)))

        let back = try await mailbox.fetch(for: [bob]).map(\.id)
        let places = try written.map { try #require(back.firstIndex(of: $0)) }

        #expect(
            places == places.sorted(),
            """
            Carol taking the first packet moved it behind the later ones for Bob. An \
            acknowledgement re-saves the record, so ordering by modification date puts the oldest \
            packet last for everyone still waiting on it, and its older `notifyWalls` wins.
            """)

        for id in written { try await mailbox.withdraw(id) }
    }

    @Test("A packet at the app's own budget is accepted by the real server")
    func aPacketAtTheBudgetIsAccepted() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let mine = LiveCloudKit.tag()

        let sent = SyncPacket(
            wraps: [mine: LiveCloudKit.bytes(48)],
            ciphertext: LiveCloudKit.bytes(SyncSession.packetByteBudget))
        try await mailbox.put(sent)

        #expect(
            (try await mailbox.fetch(for: [mine])).contains { $0.id == sent.id },
            """
            A packet at `SyncSession.packetByteBudget` did not survive a real account, so the budget \
            is above what the server will take and every large round fails in the field and nowhere \
            else.
            """)

        try await mailbox.withdraw(sent.id)
    }

    @Test("A packet over the ceiling is refused, and says which refusal it is")
    func aPacketOverTheCeilingIsRefused() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let mine = LiveCloudKit.tag()

        let huge = SyncPacket(
            wraps: [mine: LiveCloudKit.bytes(48)],
            ciphertext: LiveCloudKit.bytes(MailboxRules.recordByteCeiling + 200_000))

        var refusal: (any Error)?
        do {
            try await mailbox.put(huge)
        } catch {
            refusal = error
        }

        let caught = try #require(
            refusal,
            """
            An oversized packet was written. The ceiling is the app's own and not the server's — \
            measured 2026-09-14, CloudKit accepted a sixteen-megabyte record without a word — so \
            nothing but this check keeps a round small, and the in-memory mailbox enforced it from \
            the day it was written while the real one did not.
            """)
        var isTooLarge = false
        if case .recordTooLarge = caught as? MailboxError { isTooLarge = true }
        #expect(
            isTooLarge,
            """
            The refusal came back as \(String(describing: caught)) rather than \
            `MailboxError.recordTooLarge`. The fake and the real mailbox have to name the same \
            refusal, because `SyncSession.send` rethrows anything that is not a `MailboxFailure` — \
            an unnamed one throws out of every round, forever, with nothing a log or a member can \
            act on.
            """)

        _ = try? await mailbox.withdraw(huge.id)
    }

    @Test("A photo far over the record ceiling still goes, because it is an asset")
    func anAttachmentOverTheCeilingStillGoes() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let mine = LiveCloudKit.tag()
        let sealed = LiveCloudKit.bytes(MailboxRules.recordByteCeiling + 500_000)
        let attachment = OutgoingAttachment(id: AttachmentID(), ciphertext: sealed, recipients: [mine])

        try await mailbox.upload(attachment)
        let back = try await mailbox.download(attachment.id, hint: [mine])

        #expect(
            back == sealed,
            """
            A photo bigger than the record ceiling did not survive. The blob is written as a \
            `CKAsset` precisely so the ceiling does not apply to it; if this fails, something has \
            put the bytes back inline and every photo over a megabyte is unsendable.
            """)

        try await mailbox.delete(attachment: attachment.id)
    }

    @Test("A clip in pieces crosses the real server and opens back into the same file")
    func aClipInPiecesCrosses() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let mine = LiveCloudKit.tag()
        let source = URL.temporaryDirectory.appending(path: "live-clip-\(UUID().uuidString).mp4")
        let original = LiveCloudKit.bytes(SealedAttachment.partPlaintextBytes * 2 + 3_000_000)
        try original.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let reference = try await SealedAttachment.sealParts(of: source) { part, ciphertext in
            try await mailbox.upload(OutgoingAttachment(id: part.id, ciphertext: ciphertext, recipients: [mine]))
        }
        let parts = try #require(reference.parts)
        #expect(parts.count == 3)

        let out = URL.temporaryDirectory.appending(path: "live-opened-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        let opened = try await SealedAttachment.openParts(reference, into: out) { part in
            try await mailbox.download(part.id, hint: [mine])
        }
        #expect(opened, "a piece was missing from the server")
        #expect(try Data(contentsOf: out) == original, "the clip came back different")

        for part in parts { try await mailbox.delete(attachment: part.id) }
    }

    @Test("A receipt lands on the real server, the packet stays, and only its sender takes it back")
    func acknowledgingStopsTheOffer() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let mine = LiveCloudKit.tag()

        let sent = SyncPacket(wraps: [mine: LiveCloudKit.bytes(48)], ciphertext: LiveCloudKit.bytes(64))
        try await mailbox.put(sent)
        #expect(
            (try await mailbox.sentPackets())[sent.id]?.receipts.isEmpty == true,
            "a packet nobody has collected came back with a receipt")

        let receipt = SealedReceipt(tag: mine, sealed: LiveCloudKit.bytes(80))
        try await mailbox.acknowledge(sent.id, with: receipt)
        try await mailbox.acknowledge(sent.id, with: receipt)

        #expect(
            (try await mailbox.sentPackets())[sent.id]?.receipts == [receipt],
            """
            The receipt did not land on the real server, or landed twice. The sender takes a packet \
            back only once every recipient's device has signed for it, so a receipt that does not \
            land leaves the packet offered until it expires.
            """)
        #expect(
            (try await mailbox.fetch(for: [mine])).first { $0.id == sent.id }?.receipts == [receipt],
            "a recipient reading the zone does not see the receipts, so it would collect again")

        try await mailbox.withdraw(sent.id)
        #expect((try await mailbox.sentPackets())[sent.id] == nil, "the sender could not take its packet back")
    }
}
