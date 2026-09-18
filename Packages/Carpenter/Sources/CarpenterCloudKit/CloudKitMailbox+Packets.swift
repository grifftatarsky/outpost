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
                let outstanding = record[PacketWire.outstanding] as? [Data] ?? []
                guard outstanding.contains(where: wanted.contains) else { continue }
                guard let packet = PacketRecord.read(record) else { continue }
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

    public func pendingDeliveries() async throws -> [PacketID: Set<RecipientTag>] {
        let records = (try? await everything(in: outbox, of: container.privateCloudDatabase)) ?? []
        var waiting: [PacketID: Set<RecipientTag>] = [:]
        for record in records where record.recordType == PacketRecord.type {
            guard let id = PacketID(recordName: record.recordID.recordName) else { continue }
            let outstanding = record[PacketWire.outstanding] as? [Data] ?? []
            waiting[id] = Set(outstanding.map(RecipientTag.init(rawValue:)))
        }
        return waiting
    }

    public func acknowledge(_ id: PacketID, by tags: Set<RecipientTag>) async throws {
        try await acknowledgeRecord(named: id.recordName, by: tags)
    }

    func acknowledgeRecord(named name: String, by tags: Set<RecipientTag>) async throws {
        for attempt in 0..<Self.acknowledgementAttempts {
            do {
                try await attemptAcknowledgement(recordNamed: name, by: tags)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                guard attempt < Self.acknowledgementAttempts - 1 else { throw error }
            }
        }
    }

    private static let acknowledgementAttempts = 4

    private func attemptAcknowledgement(recordNamed name: String, by tags: Set<RecipientTag>) async throws {
        guard let (database, record) = try await locate(recordNamed: name) else {
            throw MailboxError.unknownPacket
        }

        let wanted = Set(tags.map(\.rawValue))
        var outstanding = record[PacketWire.outstanding] as? [Data] ?? []
        outstanding.removeAll { wanted.contains($0) }

        if outstanding.isEmpty {
            _ = try await database.modifyRecords(saving: [], deleting: [record.recordID])
        } else {
            record[PacketWire.outstanding] = outstanding
            _ = try await database.modifyRecords(
                saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
        }
    }
}
