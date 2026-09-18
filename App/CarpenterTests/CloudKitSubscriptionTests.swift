import CarpenterCloudKit
import CarpenterKit
import CloudKit
import Foundation
import Testing

@Suite(
    "What this device asks CloudKit to tell it about",
    .enabled(if: LiveCloudKit.isAsked),
    .serialized)
struct CloudKitSubscriptionTests {
    private static func subscriptions(_ database: CKDatabase) async throws -> [CKSubscription] {
        try await database.allSubscriptions()
    }

    @Test("Both subscriptions exist after asking for them")
    func bothSubscriptionsExist() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let registered = await mailbox.subscribeForInbox()

        #expect(
            registered.count == 2,
            """
            \(registered.count) of the two subscriptions registered. Both failures are logged and \
            swallowed, so a device that never subscribed looks exactly like one that did until \
            somebody sends it a message and nothing arrives.
            """)

        let shared = try await Self.subscriptions(CKContainer.default().sharedCloudDatabase)
        let priv = try await Self.subscriptions(CKContainer.default().privateCloudDatabase)

        #expect(
            shared.contains { $0.subscriptionID == PushChannel.inbox.subscriptionID },
            "the packet subscription is not on the shared database, which is where peers write")
        #expect(
            priv.contains { $0.subscriptionID == PushChannel.bell.subscriptionID },
            "the bell subscription is not on our own database, which is where a peer rings it")
    }

    @Test("The packet subscription is silent and names one record type")
    func theInboxSubscriptionIsSilentAndNarrow() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        await mailbox.subscribeForInbox()

        let shared = try await Self.subscriptions(CKContainer.default().sharedCloudDatabase)
        let inbox = try #require(
            shared.first { $0.subscriptionID == PushChannel.inbox.subscriptionID })

        #expect(
            (inbox as? CKDatabaseSubscription)?.recordType == PushChannel.inbox.recordType,
            """
            The packet subscription came back without the record type it was created with. A \
            subscription whose `recordType` is nil fires on **every** change in the shared \
            database — `subscriptionReport` prints "FIRES ON EVERYTHING" for exactly this, and it \
            is a battery bug nobody would ever see in a log.
            """)
        #expect(
            inbox.notificationInfo?.shouldSendContentAvailable == true,
            "the packet subscription stopped waking the app in the background")
        #expect(
            inbox.notificationInfo?.alertBody == nil,
            """
            The packet subscription would draw a banner. Packets arrive constantly and carry \
            nothing a member is meant to read; the bell is the one push they are meant to see.
            """)
    }

    @Test("The bell is visible, and scoped to this member's own zone")
    func theBellIsVisibleAndScoped() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        await mailbox.subscribeForInbox()

        let priv = try await Self.subscriptions(CKContainer.default().privateCloudDatabase)
        let bell = try #require(
            priv.first { $0.subscriptionID == PushChannel.bell.subscriptionID })
        let zoned = try #require(
            bell as? CKRecordZoneSubscription,
            "the bell is no longer scoped to a zone, so it fires for the whole private database")

        #expect(zoned.recordType == PushChannel.bell.recordType)
        #expect(zoned.zoneID.zoneName == CloudKitMailbox.outboxZoneName)
        #expect(
            bell.notificationInfo?.alertBody != nil,
            """
            The bell stopped being visible. It is the only push a member is meant to see; silent, \
            a message arrives with no banner and the app looks broken to everybody who is not \
            watching it.
            """)
    }

    @Test("Asking twice leaves one of each, not two")
    func askingTwiceDoesNotDuplicate() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        await mailbox.subscribeForInbox()
        await mailbox.subscribeForInbox()

        let shared = try await Self.subscriptions(CKContainer.default().sharedCloudDatabase)
        let priv = try await Self.subscriptions(CKContainer.default().privateCloudDatabase)

        #expect(
            shared.count { $0.subscriptionID == PushChannel.inbox.subscriptionID } == 1,
            "a second bring-up left a duplicate packet subscription, so every packet pushes twice")
        #expect(
            priv.count { $0.subscriptionID == PushChannel.bell.subscriptionID } == 1,
            "a second bring-up left a duplicate bell, so every message rings twice")
    }

    @Test("Anything else on the shared database is swept, and that is the rule")
    func theSweepRemovesEverythingElse() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        let database = CKContainer.default().sharedCloudDatabase

        let stray = CKDatabaseSubscription(subscriptionID: "test.stray.\(UUID().uuidString)")
        stray.recordType = PushChannel.inbox.recordType
        stray.notificationInfo = {
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            return info
        }()
        _ = try await database.modifySubscriptions(saving: [stray], deleting: [])

        await mailbox.subscribeForInbox()

        let shared = try await Self.subscriptions(database)
        #expect(
            !shared.contains { $0.subscriptionID == stray.subscriptionID },
            """
            The sweep left a subscription behind. `subscribeForInbox` deletes **everything** on the \
            shared database except its own, because a subscription from an older build keeps firing \
            forever and there is no other moment that would remove it.
            """)
        #expect(
            shared.contains { $0.subscriptionID == PushChannel.inbox.subscriptionID },
            "the sweep took the packet subscription with it")

        _ = try? await database.modifySubscriptions(
            saving: [], deleting: [stray.subscriptionID])
    }
}
