import CloudKit
import CarpenterKit
import Foundation

public struct CloudKitMailbox: Mailbox, MediaMailbox {
    public static let outboxZoneName = "Outbox"

    let container: CKContainer
    let outbox: CKRecordZone.ID
    let directory: PeerZoneDirectory

    public init(
        container: CKContainer,
        owner: CKRecordZone.ID? = nil,
        directory: PeerZoneDirectory = PeerZoneDirectory()
    ) {
        self.container = container
        outbox = owner ?? CKRecordZone.ID(zoneName: Self.outboxZoneName)
        self.directory = directory
    }

    public func prepare() async throws {
        let zone = CKRecordZone(zoneID: outbox)
        _ = try await container.privateCloudDatabase.modifyRecordZones(
            saving: [zone], deleting: [])
    }

    public func restoreDirectory() async {
        await directory.restore()
    }

    // MARK: Mailbox

    public static func refusal(for error: any Error) -> MailboxFailure? {
        guard let error = error as? CKError else { return nil }
        switch error.code {
        case .quotaExceeded: return .noRoomInICloud
        case .notAuthenticated, .accountTemporarilyUnavailable: return .notSignedIn
        case .partialFailure:
            let nested = error.partialErrorsByItemID?.values.compactMap { $0 as? CKError } ?? []
            if nested.contains(where: { $0.code == .quotaExceeded }) { return .noRoomInICloud }
            if nested.contains(where: {
                $0.code == .notAuthenticated || $0.code == .accountTemporarilyUnavailable
            }) { return .notSignedIn }
            return nil
        default: return nil
        }
    }

    public static let scannedFields: [CKRecord.FieldKey] = [
        PacketWire.packetID, PacketWire.outstanding, PacketWire.wrapTags, PacketWire.wrapValues,
        PacketWire.ciphertext, PacketWire.grantTags, PacketWire.grantValues,
        AttachmentWire.attachmentID, BellRecord.ring,
        ShareOfferRecord.sealed, ShareOfferRecord.digest,
    ]

    func everything(in zone: CKRecordZone.ID, of database: CKDatabase) async throws
        -> [CKRecord]
    {
        var records: [CKRecord] = []
        var token: CKServerChangeToken?

        while true {
            let batch = try await database.recordZoneChanges(
                inZoneWith: zone, since: token, desiredKeys: Self.scannedFields)
            for (_, result) in batch.modificationResultsByID {
                if let record = try? result.get().record { records.append(record) }
            }
            guard batch.moreComing else { return Self.inWriteOrder(records) }
            token = batch.changeToken
        }
    }

    static func inWriteOrder(_ records: [CKRecord]) -> [CKRecord] {
        records.sorted {
            let mine = $0.modificationDate ?? .distantPast
            let theirs = $1.modificationDate ?? .distantPast
            if mine != theirs { return mine < theirs }
            return $0.recordID.recordName < $1.recordID.recordName
        }
    }

    func locate(recordNamed name: String) async throws -> (CKDatabase, CKRecord)? {
        for (database, zone) in try await searchable() {
            let recordID = CKRecord.ID(recordName: name, zoneID: zone)
            do {
                return (database, try await database.record(for: recordID))
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                continue
            }
        }
        return nil
    }

    func searchable() async throws -> [(CKDatabase, CKRecordZone.ID)] {
        var targets: [(CKDatabase, CKRecordZone.ID)] = [(container.privateCloudDatabase, outbox)]
        let shared = (try? await container.sharedCloudDatabase.allRecordZones()) ?? []
        targets.append(contentsOf: shared.map { (container.sharedCloudDatabase, $0.zoneID) })
        return targets
    }

    var schemaZone: CKRecordZone.ID { CKRecordZone.ID(zoneName: "Schema") }

    func database(for scope: CKDatabase.Scope) -> CKDatabase {
        switch scope {
        case .private: container.privateCloudDatabase
        case .shared: container.sharedCloudDatabase
        case .public: container.publicCloudDatabase
        @unknown default: container.sharedCloudDatabase
        }
    }
}
