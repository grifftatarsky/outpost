import CloudKit
import CarpenterKit
import Foundation

// MARK: The outbox's share, and accepting somebody else's

extension CloudKitMailbox {
    public func shareURL() async throws -> URL {
        try await prepare()

        if let existing = try await currentShare(), let url = existing.url { return url }

        let share = CKShare(recordZoneID: outbox)
        share.publicPermission = .readWrite

        let saved = try await container.privateCloudDatabase.modifyRecords(
            saving: [share], deleting: [])
        guard let record = try saved.saveResults[share.recordID]?.get() as? CKShare,
            let url = record.url
        else {
            throw MailboxError.unavailable
        }
        return url
    }

    public func eraseOutbox() async throws {
        _ = try await container.privateCloudDatabase.modifyRecordZones(
            saving: [], deleting: [outbox])
        Diagnostics.sync.notice("mailbox: erased this member's outbox zone and its share")
    }

    private func currentShare() async throws -> CKShare? {
        let zones = try await container.privateCloudDatabase.allRecordZones()
        guard let zone = zones.first(where: { $0.zoneID == outbox }),
            let shareID = zone.share
        else { return nil }
        return try await container.privateCloudDatabase.record(for: shareID.recordID) as? CKShare
    }

    public static func accept(_ url: URL, in container: CKContainer) async throws {
        let metadata = try await container.shareMetadata(for: url)
        _ = try await container.accept(metadata)
    }
}
