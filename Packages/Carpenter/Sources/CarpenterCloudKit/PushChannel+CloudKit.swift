import CarpenterKit
import CloudKit

extension PushChannel {
    var notificationInfo: CKSubscription.NotificationInfo {
        let info = CKSubscription.NotificationInfo()

        guard isVisible else {
            info.shouldSendContentAvailable = true
            return info
        }

        info.alertBody = MessageNotification.generic.title
        info.soundName = "default"
        info.shouldSendMutableContent = true
        return info
    }

    func subscription(inZone zone: CKRecordZone.ID? = nil) -> CKSubscription {
        let subscription: CKSubscription

        if let zone {
            let zoned = CKRecordZoneSubscription(zoneID: zone, subscriptionID: subscriptionID)
            zoned.recordType = recordType
            subscription = zoned
        } else {
            let database = CKDatabaseSubscription(subscriptionID: subscriptionID)
            database.recordType = recordType
            subscription = database
        }

        subscription.notificationInfo = notificationInfo
        return subscription
    }
}
