import CloudKit
import CarpenterKit
import Foundation

// MARK: The single outbox every member used before, read and written only while contacts move over

extension CloudKitMailbox {
    private var oldOutbox: CKRecordZone.ID { CKRecordZone.ID(zoneName: Self.legacyZoneName) }

    func oldOutboxPackets(for tags: Set<RecipientTag>, from peer: ParticipantID) async -> [SyncPacket] {
        await index.legacy.values.flatMap { zone in
            zone.records.values.compactMap { cached -> SyncPacket? in
                guard cached.type == PacketRecord.type, var packet = PacketWire.packet(from: cached.fields),
                    !packet.recipients.isDisjoint(with: tags)
                else { return nil }
                packet.storedAt = cached.modified
                packet.from = peer
                return packet
            }
        }
    }

    func putInOldOutbox(_ record: CKRecord, fields: [String: PacketField], for peer: ParticipantID, in pairs: Pairs) async {
        guard await index.hasOldOutbox, let hint = pairs.hints[peer],
            await index.theirsFor(peer, in: pairs).isEmpty
        else { return }
        let copy = CKRecord(recordType: PacketRecord.type, recordID: CKRecord.ID(recordName: record.recordID.recordName, zoneID: oldOutbox))
        PacketRecord.write(fields, into: copy)
        do {
            try await save([copy], in: container.privateCloudDatabase)
        } catch let error as CKError where error.code == .zoneNotFound {
            await index.noteOldOutbox(false)
        } catch {
            Diagnostics.sync.error(
                "mailbox: could not leave a packet in the old outbox: \(String(describing: error), privacy: .public)")
        }
    }

    func withdrawFromOldOutbox(_ id: PacketID) async {
        guard await index.hasOldOutbox else { return }
        _ = try? await container.privateCloudDatabase.modifyRecords(
            saving: [], deleting: [CKRecord.ID(recordName: id.recordName, zoneID: oldOutbox)])
    }

    public func retireOldOutbox(whenEveryoneHasMovedAmong peers: Set<ParticipantID>, in pairs: Pairs) async {
        guard await index.hasOldOutbox else { return }
        try? await refresh()
        for peer in peers {
            guard let hint = pairs.hints[peer], await !index.theirsFor(peer, in: pairs).isEmpty else { return }
        }
        do {
            _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [oldOutbox])
            await index.noteOldOutbox(false)
            Diagnostics.sync.notice("mailbox: every contact reads a space of their own now; erased the old outbox")
        } catch {
            Diagnostics.sync.error(
                "mailbox: could not erase the old outbox: \(String(describing: error), privacy: .public)")
        }
    }

    public func eraseEverySpace() async throws {
        let zones = try await container.privateCloudDatabase.allRecordZones().map(\.zoneID).filter {
            $0.zoneName.hasPrefix(Self.pairZonePrefix) || $0.zoneName == Self.legacyZoneName
        }
        guard !zones.isEmpty else { return }
        _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: zones)
        for zone in zones { await index.dropMine(zone) }
        await index.noteOldOutbox(false)
        Diagnostics.sync.notice("mailbox: erased \(zones.count, privacy: .public) space(s) and their links")
    }
}
