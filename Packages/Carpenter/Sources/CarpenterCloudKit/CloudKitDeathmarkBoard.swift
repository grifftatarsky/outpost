import CarpenterKit
import CloudKit
import Foundation

public actor CloudKitDeathmarkBoard: DeathmarkBoard {
    public static let zoneName = "Deathmark"
    static let recordType = "Deathmark"
    static let markName = "deathmark"
    static let sealedField = "sealed"
    static let checkOffPrefix = "done-"

    private let container: CKContainer
    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: Self.zoneName) }
    private var database: CKDatabase { container.privateCloudDatabase }

    public init(container: CKContainer) {
        self.container = container
    }

    public func read() async throws -> PostedDeathmark? {
        let mark: CKRecord
        do {
            mark = try await database.record(for: CKRecord.ID(recordName: Self.markName, zoneID: zoneID))
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
        guard let sealed = mark[Self.sealedField] as? Data else { return nil }
        var checked: Set<DeviceID> = []
        var token: CKServerChangeToken?
        while true {
            let batch = try await database.recordZoneChanges(inZoneWith: zoneID, since: token, desiredKeys: [])
            for id in batch.modificationResultsByID.keys where id.recordName.hasPrefix(Self.checkOffPrefix) {
                if let device = Self.device(named: id.recordName) { checked.insert(device) }
            }
            guard batch.moreComing else { break }
            token = batch.changeToken
        }
        return PostedDeathmark(sealed: sealed, storedAt: mark.creationDate, checkedOff: checked)
    }

    public func post(_ sealed: Data) async throws {
        try await clear()
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: Self.markName, zoneID: zoneID))
        record[Self.sealedField] = sealed
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    public func checkOff(_ device: DeviceID, sealed: Data) async throws {
        let name = Self.checkOffPrefix + device.rawValue.map { String(format: "%02x", $0) }.joined()
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
        record[Self.sealedField] = sealed
        do {
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        } catch let error as CKError where error.code == .zoneNotFound {
            return
        }
    }

    public func clear() async throws {
        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            return
        }
    }

    public func eraseEverythingElse() async throws {
        let zones = try await database.allRecordZones().map(\.zoneID)
            .filter { $0.zoneName != CKRecordZone.ID.defaultZoneName && $0.zoneName != Self.zoneName }
        guard !zones.isEmpty else { return }
        _ = try await database.modifyRecordZones(saving: [], deleting: zones)
    }

    static func device(named name: String) -> DeviceID? {
        let digits = Array(name.dropFirst(checkOffPrefix.count))
        guard !digits.isEmpty, digits.count % 2 == 0 else { return nil }
        var bytes = Data()
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let byte = UInt8(String(digits[index...index + 1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        return DeviceID(rawValue: bytes)
    }
}
