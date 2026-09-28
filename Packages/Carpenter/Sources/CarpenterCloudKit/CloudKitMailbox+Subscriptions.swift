import CloudKit
import CarpenterKit
import Foundation

// MARK: What this device asks to be told about

extension CloudKitMailbox {
    @discardableResult
    public func subscribeForInbox() async -> [CKSubscription.ID] {
        let wanted = [PushChannel.inbox, PushChannel.ring]
        do {
            try await seedRecordTypes()
        } catch {
            Diagnostics.sync.error(
                "push: could not make sure the ring's record type exists: \(String(describing: error), privacy: .public)")
            return []
        }
        do {
            var standing: [CKSubscription] = []
            do {
                standing = try await container.sharedCloudDatabase.allSubscriptions()
            } catch {
                Diagnostics.sync.error(
                    """
                    push: could not read the standing subscriptions, so nothing was swept — one \
                    naming a record type this container does not have fails the whole read, and \
                    then every stale subscription keeps firing: \
                    \(String(describing: error), privacy: .public)
                    """)
            }
            let keep = Set(wanted.map(\.subscriptionID))
            let stale = standing.map(\.subscriptionID).filter { !keep.contains($0) }
            _ = try await container.sharedCloudDatabase.modifySubscriptions(
                saving: wanted.map { $0.subscription() }, deleting: stale)
            _ = try? await container.privateCloudDatabase.modifySubscriptions(saving: [], deleting: ["outpost.bell.v1"])
            Diagnostics.sync.notice(
                """
                push: watching contacts' spaces — silently for packets, visibly for rings only; \
                swept \(stale.count, privacy: .public) stale
                """)
            return wanted.map(\.subscriptionID)
        } catch {
            Diagnostics.sync.error(
                "push: could not subscribe: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private func seedRecordTypes() async throws {
        let schema = CKRecordZone.ID(zoneName: "Schema")
        let database = container.privateCloudDatabase
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: schema)], deleting: [])
        let seeds = [PacketRecord.type, PairWire.ringType, PairWire.receiptType, PairWire.infoType].map { type in
            let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: "seed-\(type)", zoneID: schema))
            record[PairWire.ring] = "0"
            return record
        }
        _ = try await database.modifyRecords(saving: seeds, deleting: [], savePolicy: .allKeys)
        _ = try? await database.modifyRecords(saving: [], deleting: seeds.map(\.recordID))
    }

    public func subscriptionReport() async -> String {
        func describe(_ database: CKDatabase, _ label: String) async -> [String] {
            guard let all = try? await database.allSubscriptions() else {
                return ["\(label): could not read subscriptions"]
            }
            if all.isEmpty { return ["\(label): none"] }
            return all.map { subscription in
                let type =
                    (subscription as? CKDatabaseSubscription)?.recordType
                    ?? (subscription as? CKRecordZoneSubscription)?.recordType
                    ?? (subscription as? CKQuerySubscription)?.recordType
                let info = subscription.notificationInfo
                let visible = info?.alertBody != nil || info?.shouldBadge == true
                return """
                    \(label): \(subscription.subscriptionID) \
                    recordType=\(type ?? "nil — FIRES ON EVERYTHING") \
                    \(visible ? "VISIBLE" : "silent") \
                    contentAvailable=\(info?.shouldSendContentAvailable == true)
                    """
            }
        }

        var lines = await describe(container.sharedCloudDatabase, "shared")
        lines.append(contentsOf: await describe(container.privateCloudDatabase, "private"))
        return lines.joined(separator: "\n")
    }
}
