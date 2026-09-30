import CloudKit
import CarpenterKit
import Foundation

// MARK: Photos and clips: one copy in the space of each person they are for, sealed for that pair

extension CloudKitMailbox {
    public func upload(_ copies: PhotoCopies, in pairs: Pairs) async throws {
        var scratch: [URL] = []
        defer { for file in scratch { try? FileManager.default.removeItem(at: file) } }

        var records: [CKRecord] = []
        var written: [(CKRecordZone.ID, String, [String: PacketField])] = []
        for (peer, copy) in copies.copies {
            let zone = try await zone(for: peer, in: pairs)
            let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sealed")
            try copy.sealed.write(to: file, options: .atomic)
            scratch.append(file)
            let record = CKRecord(
                recordType: AttachmentRecord.type, recordID: CKRecord.ID(recordName: copy.name.recordName, zoneID: zone))
            var fields = AttachmentWire.fields(of: copy)
            fields[AttachmentWire.blob] = nil
            PacketRecord.write(fields, into: record)
            record[AttachmentWire.blob] = CKAsset(fileURL: file)
            records.append(record)
            written.append((zone, copy.name.recordName, fields))
        }
        guard !records.isEmpty else { return }
        try await save(records, in: container.privateCloudDatabase)
        for (zone, name, fields) in written {
            await index.wrote(name, PairIndex.Cached(type: AttachmentRecord.type, fields: fields, at: Date()), in: zone)
        }
        Diagnostics.sync.notice(
            "mailbox: uploaded \(records.count, privacy: .public) sealed copy(ies) of an attachment")
    }

    public func download(_ copy: PhotoCopyName, of photo: AttachmentID, from sender: ParticipantID, in pairs: Pairs)
        async throws -> Data?
    {
        _ = try pairs.hint(for: sender)
        try await refresh()
        var places: [(CKRecordZone.ID, String)] = []
        for zone in await index.theirsFor(sender, in: pairs) { places.append((zone, copy.recordName)) }
        for zone in await index.legacy.keys { places.append((zone, photo.recordName)) }
        for (zone, name) in places {
            do {
                let record = try await container.sharedCloudDatabase.record(for: CKRecord.ID(recordName: name, zoneID: zone))
                guard record.recordType == AttachmentRecord.type, let asset = record[AttachmentWire.blob] as? CKAsset,
                    let url = asset.fileURL
                else { continue }
                return try Data(contentsOf: url)
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                continue
            }
        }
        return nil
    }

    public func acknowledge(
        copy: PhotoCopyName, from sender: ParticipantID, with receipt: SealedReceipt, by device: DeviceID,
        in pairs: Pairs
    ) async throws {
        try await answer(copy.receiptName(by: device), with: receipt, to: sender, in: pairs)
    }

    public func ownCopy(_ copy: PhotoCopyName, in pairs: Pairs) async throws -> Data? {
        try await refresh()
        for (_, hint) in pairs.hints {
            guard let zone = await index.mineFor(hint), await index.mine[zone]?.records[copy.recordName] != nil
            else { continue }
            do {
                let record = try await container.privateCloudDatabase.record(
                    for: CKRecord.ID(recordName: copy.recordName, zoneID: zone))
                guard let asset = record[AttachmentWire.blob] as? CKAsset, let url = asset.fileURL else { continue }
                return try Data(contentsOf: url)
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                continue
            }
        }
        return nil
    }

    public func storedCopies(in pairs: Pairs) async throws -> [StoredPhotoCopy] {
        try await refresh()
        var found: [StoredPhotoCopy] = []
        for (peer, hint) in pairs.hints {
            guard let zone = await index.mineFor(hint), let mine = await index.mine[zone] else { continue }
            let answers = await index.theirZone(for: peer, in: pairs)?.records ?? [:]
            for (recordName, cached) in mine.records where cached.type == AttachmentRecord.type {
                guard let name = PhotoCopyName(recordName: recordName) else { continue }
                found.append(
                    AttachmentWire.stored(
                        name, fields: cached.fields, to: peer, storedAt: cached.created, modifiedAt: cached.modified,
                        answeredBy: name.receiptsAmong(answers.keys).compactMap { answered in
                            answers[answered].map { (fields: $0.fields, modifiedAt: $0.modified) }
                        }))
            }
        }
        return found
    }

    public func delete(copies: Set<PhotoCopyName>, in pairs: Pairs) async throws {
        try await remove(Set(copies.map(\.recordName)))
    }
}
