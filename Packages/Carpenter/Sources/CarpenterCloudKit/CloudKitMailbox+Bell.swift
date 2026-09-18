import CloudKit
import CarpenterKit
import Foundation

// MARK: The one push a member is meant to see

extension CloudKitMailbox {
    public func ring(_ bell: MessageBell) async throws {
        guard let (zone, scope) = await directory.place(for: bell.fetchTag) else {
            Diagnostics.sync.notice(
                "mailbox: no bell for a peer whose mailbox this device has not seen yet")
            return
        }
        guard scope == .shared else { return }

        let record = CKRecord(
            recordType: BellRecord.type,
            recordID: CKRecord.ID(recordName: bell.name, zoneID: zone))
        record[BellRecord.ring] = Int64(bell.ring)

        _ = try await container.sharedCloudDatabase.modifyRecords(
            saving: [record], deleting: [], savePolicy: .allKeys)
        Diagnostics.sync.notice("mailbox: rang a peer's bell")
    }

    enum BellRecord {
        static let type = PushChannel.bell.recordType
        static let ring = "ring"
    }

    func seedBellRecordType() async throws {
        _ = try await container.privateCloudDatabase.modifyRecordZones(
            saving: [CKRecordZone(zoneID: schemaZone)], deleting: [])

        let id = CKRecord.ID(recordName: "bell-schema-seed", zoneID: schemaZone)
        let record = CKRecord(recordType: BellRecord.type, recordID: id)
        record[BellRecord.ring] = Int64(0)
        _ = try await container.privateCloudDatabase.modifyRecords(
            saving: [record], deleting: [], savePolicy: .allKeys)
        _ = try? await container.privateCloudDatabase.modifyRecords(saving: [], deleting: [id])
        Diagnostics.sync.notice("bell: record type present")
    }
}
