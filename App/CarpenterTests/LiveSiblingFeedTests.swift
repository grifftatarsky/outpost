import CarpenterCloudKit
import CarpenterKit
import CloudKit
import Foundation
import Testing

@Suite(
    "The sibling feed on a real CloudKit account",
    .enabled(if: LiveCloudKit.isAsked),
    .serialized)
struct LiveSiblingFeedTests {

    private static let zoneName = "SiblingFeeds"

    private func device() -> DeviceID {
        DeviceID(rawValue: Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }))
    }

    private func store() -> FileDocumentStore {
        FileDocumentStore(
            url: URL.temporaryDirectory
                .appending(path: "carpenter-sibling-\(UUID().uuidString)")
                .appending(path: "engine.json"))
    }

    private func feed(carrying material: Data) -> SiblingFeed {
        SiblingFeed(
            entries: [],
            certificates: [],
            epochs: [
                HeldEpoch(
                    room: RoomID(rawValue: UUID()), epoch: EpochNumber(rawValue: 3),
                    material: material)
            ],
            member: nil, writtenAt: Date())
    }

    private func record(_ name: SiblingRecord.Name) async throws -> CKRecord? {
        let id = CKRecord.ID(
            recordName: name.recordName, zoneID: CKRecordZone.ID(zoneName: Self.zoneName))
        return try? await CKContainer.default().privateCloudDatabase.record(for: id)
    }

    private func mail(_ number: Int, from device: DeviceID, carrying material: Data, for identity: Identity)
        throws -> SiblingRecord
    {
        SiblingRecord(
            name: SiblingRecord.Name(writer: device, kind: .mail(number)),
            sealed: try SealedSiblingFeed.seal(
                feed(carrying: material), for: identity, on: device, as: .mail(number)))
    }

    @Test("What reaches the server is ciphertext, and the epoch secret is not in it")
    func theWireCarriesNoSecret() async throws {
        guard LiveCloudKit.isAsked else { return }
        let identity = Identity.generate()
        let mine = device()
        let material = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })

        let sent = try mail(1, from: mine, carrying: material, for: identity)
        let sealed = sent.sealed

        let sync = CloudKitEntrySync(
            container: .default(), device: mine, stateStore: store())
        try await sync.start()
        try await sync.send([sent], deleting: [])

        var found: CKRecord?
        for _ in 0..<30 {
            if let record = try await record(sent.name) {
                found = record
                break
            }
            try? await Task.sleep(for: .seconds(2))
        }

        let record = try #require(
            found,
            """
            The sibling feed never reached CloudKit within a minute. CKSyncEngine uploads on its own \
            schedule, so a miss here is as likely to be timing as breakage — but it means this run \
            proved nothing, which is worse than a failure that says so.
            """)

        let payload = try #require(
            record["feed"] as? Data, "the record carried no feed field at all")

        #expect(
            payload.range(of: material) == nil,
            """
            THE EPOCH SECRET IS ON THE WIRE IN THE CLEAR. This is exactly the defect that stood for \
            four weeks from 2026-08-16: record[key] is not encrypted, and encryptedValues is only \
            end-to-end when the member has Advanced Data Protection on. Everything must be sealed by \
            the app before the bytes reach a transport.
            """)
        #expect(
            payload == sealed.ciphertext,
            "the bytes on the server are not the ciphertext the app sealed")

        let reopened = try SealedSiblingFeed(ciphertext: payload).open(
            with: identity, from: mine, as: .mail(1))
        #expect(reopened.epochs.first?.material == material, "the round trip lost the secret")
        #expect(
            throws: (any Error).self,
            "a stranger's identity opened a feed read back off the real server"
        ) {
            try SealedSiblingFeed(ciphertext: payload).open(
                with: Identity.generate(), from: mine, as: .mail(1))
        }

        try? await sync.forgetOwnContribution()
    }

    @Test("A second device on the same account is handed the mail, still sealed, and it is then deleted")
    func aSiblingReceivesIt() async throws {
        guard LiveCloudKit.isAsked else { return }
        let identity = Identity.generate()
        let first = device()
        let second = device()
        let material = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })

        let writer = CloudKitEntrySync(
            container: .default(), device: first, stateStore: store())
        try await writer.start()
        let sent = try mail(1, from: first, carrying: material, for: identity)
        try await writer.send([sent], deleting: [])

        var landed = false
        for _ in 0..<30 {
            if try await record(sent.name) != nil {
                landed = true
                break
            }
            try? await Task.sleep(for: .seconds(2))
        }
        guard landed else {
            Issue.record("the first device's feed never reached the server; nothing to receive")
            return
        }

        let inbox = Inbox()
        let reader = CloudKitEntrySync(
            container: .default(), device: second, stateStore: store())
        await reader.onIncoming { record in
            await inbox.record(record.sealed, record.name.writer)
        }
        try await reader.start()

        var received: (SealedSiblingFeed, DeviceID)?
        for _ in 0..<30 {
            try? await reader.refresh()
            if let hit = await inbox.first(from: first) {
                received = hit
                break
            }
            try? await Task.sleep(for: .seconds(2))
        }

        let (sealed, from) = try #require(
            received,
            """
            A second device on the same account never saw the first device's feed over real \
            CloudKit. This is the seam a member with two devices depends on to be one member.
            """)
        #expect(from == first, "the feed was attributed to the wrong device")

        let opened = try sealed.open(with: identity, from: first, as: .mail(1))
        #expect(
            opened.epochs.first?.material == material,
            "the sibling received the record but could not read the epoch out of it")

        try await writer.send([], deleting: [sent.name])
        var gone = false
        for _ in 0..<30 {
            if try await record(sent.name) == nil {
                gone = true
                break
            }
            try? await Task.sleep(for: .seconds(2))
        }
        #expect(gone, "mail its writer deleted was still on the server a minute later")

        try? await writer.forgetOwnContribution()
        try? await reader.forgetOwnContribution()
    }

    private actor Inbox {
        private var seen: [(SealedSiblingFeed, DeviceID)] = []

        func record(_ feed: SealedSiblingFeed, _ from: DeviceID) {
            seen.append((feed, from))
        }

        func first(from device: DeviceID) -> (SealedSiblingFeed, DeviceID)? {
            seen.first { $0.1 == device }
        }
    }
}
