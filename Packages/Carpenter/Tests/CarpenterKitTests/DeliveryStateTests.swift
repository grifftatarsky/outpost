import CarpenterKit
import Foundation
import Testing

@Suite("Delivery marks", .tags(.sync))
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

    @Test("An exact time is the minute it happened, with the day once it is not today, and the year once it is not this year")
    func exactFormatting() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let formatter = RelativeTimestampFormatter(calendar: calendar, locale: Locale(identifier: "en_US"))
        let at = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 15, minute: 4)))

        let today = formatter.exact(at, now: at.addingTimeInterval(600))
        #expect(today.contains("3:04"), "today read \(today)")
        #expect(!today.contains("Nov"), "today carried a date it does not need: \(today)")
        #expect(!today.contains("Yesterday"))

        let lastWeek = formatter.exact(at, now: at.addingTimeInterval(6 * 86_400))
        #expect(lastWeek.contains("Nov 4") && lastWeek.contains("3:04"), "a day this week read \(lastWeek)")
        #expect(!lastWeek.contains("2026"))

        let lastYear = formatter.exact(at, now: at.addingTimeInterval(70 * 86_400))
        #expect(lastYear.contains("2026") && lastYear.contains("3:04"), "a time last year read \(lastYear)")
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

@Suite(.tags(.sync)) struct NoRecipientsStateTests {
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
