#if DEBUG

    import CarpenterUI
    import CloudKit
    import UserNotifications

    enum ContactSpaceTest {
        static let link = CKRecord.ID(recordName: "pair-notify-test")
        static let messages = "pair-notify-messages"
        static let anything = "pair-notify-anything"

        @MainActor
        static func run(_ step: ContactSpaceStep) async -> [String] {
            let container = CKContainer.default()
            let shared = container.sharedCloudDatabase
            do {
                switch step {
                case .join:
                    let record = try await container.publicCloudDatabase.record(for: link)
                    guard let text = record["url"] as? String, let url = URL(string: text) else {
                        return ["The test link record holds no link"]
                    }
                    let metadata = try await container.shareMetadata(for: url)
                    _ = try await container.accept(metadata)
                    return ["Joined \(metadata.share.recordID.zoneID.zoneName)"]
                case .watch:
                    let scoped = CKDatabaseSubscription(subscriptionID: messages)
                    scoped.recordType = "PairNotifyMessage"
                    scoped.notificationInfo = alert("Test: a message record changed")
                    let everything = CKDatabaseSubscription(subscriptionID: anything)
                    everything.notificationInfo = alert("Test: anything changed")
                    _ = try await shared.modifySubscriptions(saving: [scoped, everything], deleting: [])
                    return ["Watching for message records, and for anything"]
                case .check:
                    let standing = try await shared.allSubscriptions().map(\.subscriptionID)
                    let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
                    let format = DateFormatter()
                    format.dateFormat = "HH:mm:ss"
                    let arrived = delivered.compactMap { notification -> (Date, String)? in
                        let id = CKNotification(
                            fromRemoteNotificationDictionary: notification.request.content.userInfo)?.subscriptionID
                        guard let id, [messages, anything].contains(id) else { return nil }
                        return (notification.date, id)
                    }
                    .sorted { $0.0 < $1.0 }
                    .map { "\(format.string(from: $0.0))  \($0.1)" }
                    return ["Standing: \(standing.sorted().joined(separator: ", "))", "Arrived: \(arrived.count)"]
                        + arrived
                case .remove:
                    _ = try? await shared.modifySubscriptions(saving: [], deleting: [messages, anything])
                    let zones = try await shared.allRecordZones().map(\.zoneID).filter { $0.zoneName == "PairNotify" }
                    if !zones.isEmpty { _ = try await shared.modifyRecordZones(saving: [], deleting: zones) }
                    return ["Removed both watches and left \(zones.count) test space(s)"]
                }
            } catch {
                return ["Failed: \(error)"]
            }
        }

        private static func alert(_ body: String) -> CKSubscription.NotificationInfo {
            let info = CKSubscription.NotificationInfo()
            info.alertBody = body
            info.soundName = "default"
            return info
        }
    }

#endif
