import CloudKit
import CarpenterKit
import Foundation

// MARK: Photos and clips: one copy in the space of each person they are for

extension CloudKitMailbox {
    static func photoRecordName(_ id: AttachmentID) -> String { LocalPairStore.photoPrefix + id.recordName }

    public func upload(_ attachment: OutgoingAttachment, in pairs: Pairs) async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sealed")
        try attachment.ciphertext.write(to: scratch, options: .atomic)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var records: [CKRecord] = []
        var written: [(CKRecordZone.ID, [String: PacketField])] = []
        for (peer, tag) in attachment.recipients {
            let zone = try await zone(for: peer, in: pairs)
            let record = CKRecord(
                recordType: AttachmentRecord.type,
                recordID: CKRecord.ID(recordName: Self.photoRecordName(attachment.id), zoneID: zone))
            var fields = AttachmentWire.fields(of: attachment, for: tag)
            fields[AttachmentWire.blob] = nil
            PacketRecord.write(fields, into: record)
            record[AttachmentWire.blob] = CKAsset(fileURL: scratch)
            records.append(record)
            written.append((zone, fields))
        }
        guard !records.isEmpty else { return }
        try await save(records, in: container.privateCloudDatabase)
        for (zone, fields) in written {
            await index.wrote(
                Self.photoRecordName(attachment.id), PairIndex.Cached(type: AttachmentRecord.type, fields: fields, at: Date()),
                in: zone)
        }
        Diagnostics.sync.notice(
            """
            mailbox: uploaded an attachment of \(attachment.ciphertext.count, privacy: .public) bytes \
            for \(records.count, privacy: .public) person(s)
            """)
    }

    public func download(_ id: AttachmentID, from sender: ParticipantID, in pairs: Pairs) async throws -> Data? {
        let hint = try pairs.hint(for: sender)
        try await refresh()
        var places: [(CKRecordZone.ID, String)] = []
        for zone in await index.theirsFor(sender, in: pairs) { places.append((zone, Self.photoRecordName(id))) }
        for zone in await index.legacy.keys { places.append((zone, id.recordName)) }
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
        attachment id: AttachmentID, from sender: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs
    ) async throws {
        try await answer(PairWire.receiptName(for: id), with: receipt, to: sender, in: pairs)
    }

    public func pendingAttachments(in pairs: Pairs) async throws -> [AttachmentID: SentAttachment] {
        try await refresh()
        var recipients: [AttachmentID: Set<RecipientTag>] = [:]
        var receipts: [AttachmentID: [SealedReceipt]] = [:]
        for (peer, hint) in pairs.hints {
            guard let zone = await index.mineFor(hint), let mine = await index.mine[zone] else { continue }
            let answers = await index.theirZone(for: peer, in: pairs)?.records ?? [:]
            for (name, cached) in mine.records where cached.type == AttachmentRecord.type {
                guard name.hasPrefix(LocalPairStore.photoPrefix),
                    let id = AttachmentID(recordName: String(name.dropFirst(LocalPairStore.photoPrefix.count)))
                else { continue }
                recipients[id, default: []].formUnion(AttachmentWire.recipients(in: cached.fields))
                if let answer = answers[PairWire.receiptName(for: id)], answer.modified >= cached.modified,
                    let receipt = PacketWire.receipt(from: answer.fields)
                {
                    receipts[id, default: []].append(receipt)
                }
            }
        }
        return recipients.reduce(into: [:]) { found, entry in
            found[entry.key] = SentAttachment(recipients: entry.value, receipts: receipts[entry.key] ?? [])
        }
    }

    public func sweepableAttachments(in pairs: Pairs) async throws -> [AttachmentID: Date] {
        try await refresh()
        let settled = Date().addingTimeInterval(-MailboxRules.sweepAge)
        var found: [AttachmentID: Date] = [:]
        for zone in await index.mine.values {
            for (name, cached) in zone.records where cached.type == AttachmentRecord.type && cached.created < settled {
                guard let id = AttachmentID(recordName: String(name.dropFirst(LocalPairStore.photoPrefix.count))) else {
                    continue
                }
                found[id] = max(found[id] ?? .distantPast, cached.modified)
            }
        }
        return found
    }

    public func delete(attachment id: AttachmentID, in pairs: Pairs) async throws {
        try await remove(Self.photoRecordName(id))
    }
}
