import CloudKit
import CarpenterKit
import Foundation

// MARK: Packets, rings and receipts, each written only into this member's own space for one person

extension CloudKitMailbox {
    public func put(_ packet: SyncPacket, to peer: ParticipantID, in pairs: Pairs) async throws {
        let fields = PacketWire.fields(of: packet)
        let weight = MailboxRules.weigh(fields)
        guard weight <= MailboxRules.recordByteCeiling else {
            throw MailboxError.recordTooLarge(bytes: weight, ceiling: MailboxRules.recordByteCeiling)
        }
        let zone = try await zone(for: peer, in: pairs)
        let record = CKRecord(recordType: PacketRecord.type, recordID: CKRecord.ID(recordName: packet.id.recordName, zoneID: zone))
        PacketRecord.write(fields, into: record)
        try await save([record], in: container.privateCloudDatabase)
        await index.wrote(packet.id.recordName, PairIndex.Cached(type: PacketRecord.type, fields: fields, at: Date()), in: zone)
        await putInOldOutbox(record, fields: fields, for: peer, in: pairs)
    }

    public func ring(_ peer: ParticipantID, in pairs: Pairs) async throws {
        let zone = try await zone(for: peer, in: pairs)
        let record = CKRecord(recordType: PairWire.ringType, recordID: CKRecord.ID(recordName: PairWire.ringRecord, zoneID: zone))
        record[PairWire.ring] = PairWire.ringValue()
        try await save([record], in: container.privateCloudDatabase)
    }

    public func fetch(from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs) async throws
        -> [SyncPacket]
    {
        let hint = try pairs.hint(for: peer)
        try await refresh()
        let theirs = await index.theirZone(for: peer, in: pairs)
        let mine = await index.myZone(for: hint)
        var found = packets(in: theirs, for: tags, from: peer, answeredIn: mine)
        found += await oldOutboxPackets(for: tags, from: peer)
        if let theirs { await clearAnswered(to: peer, hint: hint, holding: Set(theirs.records.keys)) }
        return found
    }

    public func acknowledge(
        _ id: PacketID, from peer: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs
    ) async throws {
        try await answer(PairWire.receiptName(for: id), with: receipt, to: peer, in: pairs)
    }

    public func sentPackets(in pairs: Pairs) async throws -> [PacketID: SentPacket] {
        try await refresh()
        var sent: [PacketID: SentPacket] = [:]
        for (peer, hint) in pairs.hints {
            guard let zone = await index.mineFor(hint), let mine = await index.mine[zone] else { continue }
            let answers = await index.theirZone(for: peer, in: pairs)?.records ?? [:]
            for (name, cached) in mine.records where cached.type == PacketRecord.type {
                guard let id = PacketID(recordName: name), let packet = PacketWire.packet(from: cached.fields) else { continue }
                let receipt = answers[PairWire.receiptName(for: id)].flatMap { PacketWire.receipt(from: $0.fields) }
                sent[id] = SentPacket(
                    to: peer, recipients: packet.recipients, receipts: receipt.map { [$0] } ?? [],
                    createdAt: cached.created, contentDigest: packet.contentDigest)
            }
        }
        return sent
    }

    public func withdraw(_ id: PacketID, in pairs: Pairs) async throws {
        try await remove([id.recordName])
        await withdrawFromOldOutbox(id)
    }

    // MARK: Shared by packets and photos

    func answer(_ name: String, with receipt: SealedReceipt, to peer: ParticipantID, in pairs: Pairs) async throws {
        let zone = try await zone(for: peer, in: pairs)
        let fields = PacketWire.receiptFields(receipt)
        let record = CKRecord(recordType: PairWire.receiptType, recordID: CKRecord.ID(recordName: name, zoneID: zone))
        PacketRecord.write(fields, into: record)
        try await save([record], in: container.privateCloudDatabase)
        await index.wrote(name, PairIndex.Cached(type: PairWire.receiptType, fields: fields, at: Date()), in: zone)
    }

    func remove(_ names: Set<String>) async throws {
        let ids = await index.mine.flatMap { zone, found in
            names.filter { found.records[$0] != nil }.map { CKRecord.ID(recordName: $0, zoneID: zone) }
        }
        guard !ids.isEmpty else { return }
        _ = try await container.privateCloudDatabase.modifyRecords(saving: [], deleting: ids)
        for id in ids { await index.removed(id.recordName, from: id.zoneID) }
    }

    private func packets(
        in theirs: PairIndex.Zone?, for tags: Set<RecipientTag>, from peer: ParticipantID, answeredIn mine: PairIndex.Zone?
    ) -> [SyncPacket] {
        guard let theirs else { return [] }
        return theirs.records
            .filter { $0.value.type == PacketRecord.type }
            .sorted { $0.value.created != $1.value.created ? $0.value.created < $1.value.created : $0.key < $1.key }
            .compactMap { name, cached in
                guard var packet = PacketWire.packet(from: cached.fields), !packet.recipients.isDisjoint(with: tags) else {
                    return nil
                }
                packet.storedAt = cached.modified
                packet.from = peer
                if let answer = mine?.records[PairWire.receiptName(for: packet.id)],
                    let receipt = PacketWire.receipt(from: answer.fields)
                {
                    packet.receipts = [receipt]
                }
                return packet
            }
    }

    private func clearAnswered(to peer: ParticipantID, hint: PairHint, holding held: Set<String>) async {
        guard let zone = await index.mineFor(hint), let mine = await index.mine[zone] else { return }
        let settled = Date().addingTimeInterval(-MailboxRules.sweepAge)
        let stale = mine.records.filter { name, cached in
            guard cached.type == PairWire.receiptType, cached.created < settled else { return false }
            if let packet = PairWire.packet(fromReceiptName: name) { return !held.contains(packet.recordName) }
            if let copy = PhotoCopyName(receiptName: name) { return !held.contains(copy.recordName) }
            return false
        }.map(\.key)
        guard !stale.isEmpty else { return }
        let ids = stale.map { CKRecord.ID(recordName: $0, zoneID: zone) }
        guard (try? await container.privateCloudDatabase.modifyRecords(saving: [], deleting: ids)) != nil else { return }
        for name in stale { await index.removed(name, from: zone) }
    }
}
