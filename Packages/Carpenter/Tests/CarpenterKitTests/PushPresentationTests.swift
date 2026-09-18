import CarpenterKit
import Testing
import UserNotifications

@testable import CarpenterApp

@Suite("Which pushes the member is allowed to see")
struct PushPresentationTests {
    @Test("A bell shows a banner")
    func bellShowsBanner() {
        let options = PushPresentation.options(forSubscriptionID: PushChannel.bell.subscriptionID)
        #expect(options.contains(.banner), "an incoming message would arrive invisibly")
    }

    @Test("Packet and sibling-feed pushes show nothing")
    func silentChannelsShowNothing() {
        #expect(
            PushPresentation.options(forSubscriptionID: PushChannel.inbox.subscriptionID).isEmpty,
            "an acknowledgement or a grant would announce itself as a message")
        #expect(
            PushPresentation.options(forSubscriptionID: PushChannel.deviceFeed.subscriptionID)
                .isEmpty,
            "the member's own write would be announced back to them")
    }

    @Test("An unrecognised or missing subscription shows nothing")
    func unknownShowsNothing() {
        #expect(PushPresentation.options(forSubscriptionID: "outpost.inbox.v1").isEmpty)
        #expect(PushPresentation.options(forSubscriptionID: nil).isEmpty)
    }

    @Test("A message for the conversation on screen shows nothing")
    func readingTheRoomSuppressesIt() {
        let bell = PushChannel.bell.subscriptionID
        let kitchen = MessageNotification.thread(for: RoomID())
        let hangar = MessageNotification.thread(for: RoomID())

        #expect(
            PushPresentation.options(forSubscriptionID: bell, thread: kitchen, viewing: kitchen)
                .isEmpty)
        #expect(
            PushPresentation.options(forSubscriptionID: bell, thread: hangar, viewing: kitchen)
                .contains(.banner),
            "a message in another room was swallowed")
        #expect(
            PushPresentation.options(forSubscriptionID: bell, thread: kitchen, viewing: nil)
                .contains(.banner),
            "a message was swallowed while no room was open")
    }

    @Test("An undecrypted banner is never mistaken for the room on screen")
    func emptyThreadIsNotAMatch() {
        let bell = PushChannel.bell.subscriptionID
        #expect(PushPresentation.options(forSubscriptionID: bell, thread: "", viewing: "").contains(.banner))
        #expect(PushPresentation.options(forSubscriptionID: bell, thread: "", viewing: nil).contains(.banner))
    }

    @Test("Exactly one channel is visible, and every channel is scoped")
    func channelTableIsHonest() {
        let visible = PushChannel.allCases.filter(\.isVisible)
        #expect(visible == [.bell], "more than one channel can produce a banner")

        for channel in PushChannel.allCases {
            #expect(
                !channel.recordType.isEmpty,
                "\(channel) is unscoped, so it fires on every record type in range")
        }
        #expect(
            Set(PushChannel.allCases.map(\.recordType)).count == PushChannel.allCases.count,
            "two channels share a record type, so one can trigger the other")
        #expect(
            Set(PushChannel.allCases.map(\.subscriptionID)).count == PushChannel.allCases.count,
            "two channels share a subscription id, so one would overwrite the other")
    }
}
