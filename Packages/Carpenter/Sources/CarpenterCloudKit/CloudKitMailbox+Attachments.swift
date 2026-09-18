import CloudKit
import CarpenterKit
import Foundation

// MARK: Photos and clips, which travel as assets

extension CloudKitMailbox {
    public func upload(_ attachment: OutgoingAttachment) async throws {
        let record = CKRecord(
            recordType: AttachmentRecord.type,
            recordID: CKRecord.ID(recordName: attachment.id.recordName, zoneID: outbox))
        let scratch = try AttachmentRecord.write(attachment, into: record)
        defer { try? FileManager.default.removeItem(at: scratch) }

        _ = try await container.privateCloudDatabase.modifyRecords(
            saving: [record], deleting: [], savePolicy: .allKeys)
        Diagnostics.sync.notice(
            """
            mailbox: uploaded an attachment of \(attachment.ciphertext.count, privacy: .public) bytes \
            for \(attachment.recipients.count, privacy: .public) recipient(s)
            """)
    }

    public func download(_ id: AttachmentID, hint tags: Set<RecipientTag>) async throws -> Data? {
        var candidates: [(CKDatabase, CKRecordZone.ID)] = []
        if tags.isEmpty {
            candidates.append((container.privateCloudDatabase, outbox))
        } else {
            for tag in tags {
                if let (zone, scope) = await directory.place(for: tag) {
                    candidates.append((database(for: scope), zone))
                    break
                }
            }
        }
        for (database, zone) in try await searchable()
        where !candidates.contains(where: { $0.1 == zone && $0.0.databaseScope == database.databaseScope }) {
            candidates.append((database, zone))
        }

        for (database, zone) in candidates {
            do {
                let record = try await database.record(
                    for: CKRecord.ID(recordName: id.recordName, zoneID: zone))
                guard record.recordType == AttachmentRecord.type,
                    let asset = record[AttachmentWire.blob] as? CKAsset,
                    let url = asset.fileURL
                else { continue }
                return try Data(contentsOf: url)
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                continue
            }
        }
        return nil
    }

    public func acknowledge(attachment id: AttachmentID, by tags: Set<RecipientTag>) async throws {
        try await acknowledgeRecord(named: id.recordName, by: tags)
    }

    public func pendingAttachments() async throws -> [AttachmentID: Set<RecipientTag>] {
        try await outstandingAttachments(olderThan: nil)
    }

    public func sweepableAttachments() async throws -> [AttachmentID: Set<RecipientTag>] {
        try await outstandingAttachments(olderThan: Date().addingTimeInterval(-MailboxRules.sweepAge))
    }

    private func outstandingAttachments(olderThan settled: Date?) async throws
        -> [AttachmentID: Set<RecipientTag>]
    {
        let records = try await everything(in: outbox, of: container.privateCloudDatabase)
        var waiting: [AttachmentID: Set<RecipientTag>] = [:]
        for record in records where record.recordType == AttachmentRecord.type {
            guard let id = AttachmentID(recordName: record.recordID.recordName) else { continue }
            if let settled, (record.creationDate ?? .distantPast) >= settled { continue }
            let outstanding = record[PacketWire.outstanding] as? [Data] ?? []
            waiting[id] = Set(outstanding.map(RecipientTag.init(rawValue:)))
        }
        return waiting
    }

    public func delete(attachment id: AttachmentID) async throws {
        _ = try await container.privateCloudDatabase.modifyRecords(
            saving: [],
            deleting: [CKRecord.ID(recordName: id.recordName, zoneID: outbox)])
    }
}
