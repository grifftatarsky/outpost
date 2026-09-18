import CloudKit
import CarpenterKit
import Foundation

// MARK: What this device asks to be told about

extension CloudKitMailbox {
    @discardableResult
    public func subscribeForInbox() async -> [CKSubscription.ID] {
        var registered: [CKSubscription.ID] = []

        let inbox = PushChannel.inbox.subscription()
        let bell = PushChannel.bell.subscription(inZone: outbox)

        do {
            var standing: [CKSubscription] = []
            do {
                standing = try await container.sharedCloudDatabase.allSubscriptions()
            } catch {
                Diagnostics.sync.error(
                    """
                    inbox: could not read the standing subscriptions, so nothing was swept — one \
                    naming a record type this container does not have fails the whole read, and \
                    then every stale subscription keeps firing: \
                    \(String(describing: error), privacy: .public)
                    """)
            }
            let stale = standing
                .map(\.subscriptionID)
                .filter { $0 != PushChannel.inbox.subscriptionID }

            _ = try await container.sharedCloudDatabase.modifySubscriptions(
                saving: [inbox], deleting: stale)
            registered.append(PushChannel.inbox.subscriptionID)
            Diagnostics.sync.notice(
                """
                inbox: subscribed silently for \(PushChannel.inbox.recordType, privacy: .public) \
                on the shared database, swept \(stale.count, privacy: .public) stale
                """)
        } catch {
            Diagnostics.sync.error(
                "inbox: could not subscribe for packet pushes: \(String(describing: error), privacy: .public)")
        }

        do {
            try await prepare()
            try? await seedBellRecordType()
            _ = try await container.privateCloudDatabase.modifySubscriptions(
                saving: [bell], deleting: [])
            registered.append(PushChannel.bell.subscriptionID)
            Diagnostics.sync.notice(
                "bell: subscribed visibly for \(PushChannel.bell.recordType, privacy: .public) on our own zone")
        } catch {
            Diagnostics.sync.error(
                "bell: could not subscribe for message pushes: \(String(describing: error), privacy: .public)")
        }

        return registered
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
