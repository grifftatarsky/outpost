import CloudKit
import CarpenterKit
import Foundation

// MARK: Writing a packet, reading one, and acknowledging it

extension CloudKitMailbox {
    public func put(_ packet: SyncPacket) async throws {
        let weight = MailboxRules.weigh(PacketWire.fields(of: packet))
        guard weight <= MailboxRules.recordByteCeiling else {
            throw MailboxError.recordTooLarge(
                bytes: weight, ceiling: MailboxRules.recordByteCeiling)
        }

        let record = CKRecord(
            recordType: PacketRecord.type,
            recordID: CKRecord.ID(recordName: packet.id.recordName, zoneID: outbox))

        try PacketRecord.write(packet, into: record)
        do {
            _ = try await container.privateCloudDatabase.modifyRecords(
                saving: [record], deleting: [], savePolicy: .allKeys)
        } catch {
            throw Self.refusal(for: error) ?? error
        }
        Diagnostics.sync.notice(
            "mailbox put: wrote a packet addressed to \(packet.wraps.count, privacy: .public) recipient(s)")
    }

    public func fetch(for tags: Set<RecipientTag>) async throws -> [SyncPacket] {
        var packets: [SyncPacket] = []
        let wanted = Set(tags.map(\.rawValue))

        let zones = try await searchable()
        var scanned = 0
        for (database, zone) in zones {
            guard let records = try? await everything(in: zone, of: database) else { continue }
            scanned += records.count

            var isOurPeer = false
            for record in records {
                guard record.recordType == PacketRecord.type else { continue }
                let addressed = record[PacketWire.wrapTags] as? [Data] ?? []
                guard addressed.contains(where: wanted.contains) else { continue }
                guard var packet = PacketRecord.read(record) else { continue }
                packet.storedAt = record.modificationDate
                packets.append(packet)
                isOurPeer = true
            }
            if isOurPeer {
                await directory.learn(zone: zone, in: database.databaseScope, for: tags)
            }
        }
        let owners = zones.map { $0.1.ownerName == CKCurrentUserDefaultName ? "own" : String($0.1.ownerName.suffix(6)) }
        Diagnostics.sync.notice(
            """
            mailbox fetch: \(zones.count, privacy: .public) zone(s) reachable \
            [\(owners.joined(separator: " "), privacy: .public)] \
            (\(scanned, privacy: .public) record(s) total), \
            \(packets.count, privacy: .public) addressed to us
            """)
        return packets
    }

    public func sentPackets() async throws -> [PacketID: SentPacket] {
        let records = (try? await everything(in: outbox, of: container.privateCloudDatabase)) ?? []
        var sent: [PacketID: SentPacket] = [:]
        for record in records where record.recordType == PacketRecord.type {
            guard let id = PacketID(recordName: record.recordID.recordName),
                let packet = PacketRecord.read(record)
            else { continue }
            sent[id] = SentPacket(
                recipients: packet.recipients, receipts: packet.receipts, createdAt: record.creationDate,
                contentDigest: packet.contentDigest)
        }
        return sent
    }

    public func acknowledge(_ id: PacketID, with receipt: SealedReceipt) async throws {
        for attempt in 0..<Self.acknowledgementAttempts {
            do {
                try await attemptAcknowledgement(recordNamed: id.recordName, with: receipt)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                guard attempt < Self.acknowledgementAttempts - 1 else { throw error }
            }
        }
    }

    private static let acknowledgementAttempts = 4

    private func attemptAcknowledgement(recordNamed name: String, with receipt: SealedReceipt) async throws {
        guard let (database, record) = try await locate(recordNamed: name) else {
            throw MailboxError.unknownPacket
        }
        var fields: [String: PacketField] = [:]
        if let tags = record[PacketWire.receiptTags] as? [Data] { fields[PacketWire.receiptTags] = .dataList(tags) }
        if let values = record[PacketWire.receiptValues] as? [Data] {
            fields[PacketWire.receiptValues] = .dataList(values)
        }
        guard PacketWire.adding(receipt, to: &fields),
            case .dataList(let tags)? = fields[PacketWire.receiptTags],
            case .dataList(let values)? = fields[PacketWire.receiptValues]
        else { return }
        record[PacketWire.receiptTags] = tags
        record[PacketWire.receiptValues] = values
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
    }

    public func withdraw(_ id: PacketID) async throws {
        _ = try await container.privateCloudDatabase.modifyRecords(
            saving: [], deleting: [CKRecord.ID(recordName: id.recordName, zoneID: outbox)])
    }
}
