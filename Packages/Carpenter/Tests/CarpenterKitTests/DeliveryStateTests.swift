import CarpenterKit
import Foundation
import Testing

@Suite("Delivery marks")
struct DeliveryStateTests {
    private let instant = Date(timeIntervalSince1970: 1_786_635_000)

    @Test("Each state fills exactly the marks it has earned")
    func marksPerState() {
        #expect(DeliveryState.pending.isVisible == false)
        #expect(DeliveryState.sent.isCollected == false)
        #expect(DeliveryState.delivered.isCollected)
        #expect(DeliveryState.delivered.wasDisplayed == false)
        #expect(DeliveryState.displayed(at: instant).isCollected)
        #expect(DeliveryState.displayed(at: instant).wasDisplayed)
    }

    @Test("Only a displayed message carries a time")
    func timeOnlyWhenDisplayed() {
        #expect(DeliveryState.pending.displayedAt == nil)
        #expect(DeliveryState.sent.displayedAt == nil)
        #expect(DeliveryState.delivered.displayedAt == nil)
        #expect(DeliveryState.displayed(at: instant).displayedAt == instant)
    }

    @Test("A read receipt reads as a time, and grows a date once it is not today")
    func receiptFormatting() {
        let formatter = RelativeTimestampFormatter()

        let today = formatter.readReceipt(instant, now: instant.addingTimeInterval(120))
        #expect(!today.isEmpty)
        #expect(!today.contains("Yesterday"))

        let yesterday = formatter.readReceipt(instant, now: instant.addingTimeInterval(26 * 3_600))
        #expect(yesterday == "Yesterday")
    }
}

@Suite struct NoRecipientsStateTests {
    @Test("A message with nobody to reach is drawn, unlike one that is merely about to go")
    func nobodyToReachIsVisible() {
        #expect(DeliveryState.pending.isVisible == false)
        #expect(DeliveryState.noRecipients.isVisible, "a state that cannot resolve must be shown")
    }

    @Test("Nothing about it claims the message got anywhere")
    func claimsNothing() {
        #expect(DeliveryState.noRecipients.isCollected == false)
        #expect(DeliveryState.noRecipients.wasDisplayed == false)
        #expect(DeliveryState.noRecipients.displayedAt == nil)
    }

    @Test("It is its own shape, not a variant of the reporting one")
    func distinctFromNotReported() {
        #expect(DeliveryState.noRecipients.hasNobodyToReach)
        #expect(DeliveryState.noRecipients.reportingIsOff == false)
        #expect(DeliveryState.notReported.hasNobodyToReach == false)
    }
}
