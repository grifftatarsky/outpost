import CloudKit
import CarpenterKit
import Foundation

// MARK: What a member can check from Settings

extension CloudKitMailbox {
    public func roundTrip(in pairs: Pairs) async -> String {
        var lines: [String] = []
        do {
            lines.append("account: \(String(try await account(in: pairs).prefix(8)))…")
            try await refresh()
        } catch {
            return "iCloud could not be read — \(error)"
        }
        let mine = await index.mine
        let theirs = await index.theirs
        let known = Set(pairs.hints.values)
        lines.append("spaces of yours: \(mine.count), for people this device knows: \(mine.values.filter { $0.hint.map(known.contains) ?? false }.count)")
        lines.append("spaces you read: \(theirs.count), from people this device knows: \(theirs.values.filter { $0.hint.map(known.contains) ?? false }.count)")
        let waiting = mine.values.reduce(0) { $0 + $1.records.values.filter { $0.type == PacketRecord.type }.count }
        lines.append("packets waiting to be collected from you: \(waiting)")
        lines.append(await index.hasOldOutbox ? "old outbox: still kept while contacts move over" : "old outbox: gone")
        return lines.joined(separator: "\n")
    }
}

extension CloudKitMailbox {
    private var timingZone: CKRecordZone.ID { CKRecordZone.ID(zoneName: "Timing") }

    public func putForTiming(_ id: AttachmentID, _ ciphertext: Data) async throws {
        let database = container.privateCloudDatabase
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: timingZone)], deleting: [])
        let scratch = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sealed")
        try ciphertext.write(to: scratch, options: .atomic)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let record = CKRecord(recordType: AttachmentRecord.type, recordID: CKRecord.ID(recordName: id.recordName, zoneID: timingZone))
        record[AttachmentWire.blob] = CKAsset(fileURL: scratch)
        try await save([record], in: database)
    }

    public func readForTiming(_ id: AttachmentID) async throws -> Data? {
        let record = try await container.privateCloudDatabase.record(for: CKRecord.ID(recordName: id.recordName, zoneID: timingZone))
        guard let url = (record[AttachmentWire.blob] as? CKAsset)?.fileURL else { return nil }
        return try Data(contentsOf: url)
    }

    @discardableResult
    public func clearTimingSpace() async -> Bool {
        (try? await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [timingZone])) != nil
    }
}
