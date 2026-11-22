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
    private static func subscriptions(_ database: CKDatabase, including wanted: [PushChannel] = []) async throws
        -> [CKSubscription]
    {
        var found = try await database.allSubscriptions()
        for _ in 0..<10 where !wanted.allSatisfy({ channel in found.contains { $0.subscriptionID == channel.subscriptionID } }) {
            try await Task.sleep(for: .seconds(1))
            found = try await database.allSubscriptions()
        }
        return found
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

        let shared = try await Self.subscriptions(CKContainer.default().sharedCloudDatabase, including: [.inbox, .ring])
        let priv = try await Self.subscriptions(CKContainer.default().privateCloudDatabase)

        #expect(
            shared.contains { $0.subscriptionID == PushChannel.inbox.subscriptionID },
            "the packet subscription is not on the shared database, which is where contacts' spaces are")
        #expect(
            shared.contains { $0.subscriptionID == PushChannel.ring.subscriptionID },
            "the ring subscription is not on the shared database, which is where a contact rings")
        #expect(
            !priv.contains { $0.subscriptionID == "outpost.bell.v1" },
            "the old bell on this member's own database was left behind; nobody can write there any more")
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

    @Test("The ring is visible and names only the ring's record type, so a receipt or a deletion wakes nobody")
    func theRingIsVisibleAndNarrow() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        await mailbox.subscribeForInbox()

        let shared = try await Self.subscriptions(CKContainer.default().sharedCloudDatabase)
        let ring = try #require(shared.first { $0.subscriptionID == PushChannel.ring.subscriptionID })
        #expect(
            (ring as? CKDatabaseSubscription)?.recordType == PairWire.ringType,
            """
            The ring came back without its record type. Measured on Griff's phone 2026-09-27: a watch \
            limited to one record type rang for that type alone, and a watch on everything rang for \
            receipts and deletions too. Without the type, every receipt a contact writes is a banner.
            """)
        #expect(
            ring.notificationInfo?.alertBody != nil,
            "the ring stopped being visible, so a message arrives with no banner")
    }

    @Test("Asking twice leaves one of each, not two")
    func askingTwiceDoesNotDuplicate() async throws {
        let mailbox = try await LiveCloudKit.mailbox()
        await mailbox.subscribeForInbox()
        await mailbox.subscribeForInbox()

        let shared = try await Self.subscriptions(CKContainer.default().sharedCloudDatabase)

        #expect(
            shared.count { $0.subscriptionID == PushChannel.inbox.subscriptionID } == 1,
            "a second bring-up left a duplicate packet subscription, so every packet pushes twice")
        #expect(
            shared.count { $0.subscriptionID == PushChannel.ring.subscriptionID } == 1,
            "a second bring-up left a duplicate ring, so every message rings twice")
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
