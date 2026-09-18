import Foundation
import Testing

@testable import CarpenterKit

@Suite("Relative timestamps")
struct RelativeTimestampTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_786_635_000)

    private func formatter(locale: Locale = Locale(identifier: "en_GB")) -> RelativeTimestampFormatter {
        RelativeTimestampFormatter(calendar: calendar, locale: locale)
    }

    private func date(daysAgo: Int = 0, hoursAgo: Int = 0, minutesAgo: Int = 0) -> Date {
        now.addingTimeInterval(-Double(daysAgo * 86_400 + hoursAgo * 3_600 + minutesAgo * 60))
    }

    // MARK: Rooms list

    @Test("Today shows the time of day")
    func roomsListToday() {
        #expect(formatter().roomsList(for: date(hoursAgo: 4, minutesAgo: 26), now: now) == "11:04")
    }

    @Test("Yesterday is named, not dated")
    func roomsListYesterday() {
        #expect(formatter().roomsList(for: date(daysAgo: 1), now: now) == "Yesterday")
    }

    @Test("Inside the last week shows the weekday in full")
    func roomsListWeekday() {
        #expect(formatter().roomsList(for: date(daysAgo: 2), now: now) == "Tuesday")
        #expect(formatter().roomsList(for: date(daysAgo: 6), now: now) == "Friday")
    }

    @Test("Older than a week falls back to a date")
    func roomsListOlder() {
        #expect(formatter().roomsList(for: date(daysAgo: 30), now: now) == "14/07/2026")
    }

    @Test("A twelve-hour locale gets a twelve-hour time")
    func roomsListRespectsLocale() {
        let us = formatter(locale: Locale(identifier: "en_US"))
        #expect(us.roomsList(for: date(hoursAgo: 4, minutesAgo: 26), now: now) == "11:04\u{202F}AM")
    }

    // MARK: Compact

    @Test("Under a minute reads as now, not as a countdown")
    func compactNow() {
        #expect(formatter().compact(for: date(minutesAgo: 0), now: now) == "now")
        #expect(formatter().compact(for: now.addingTimeInterval(-59), now: now) == "now")
    }

    @Test("Minutes and hours are counted while they are still today")
    func compactElapsed() {
        #expect(formatter().compact(for: date(minutesAgo: 42), now: now) == "42m")
        #expect(formatter().compact(for: date(hoursAgo: 4), now: now) == "4h")
    }

    @Test("Past today the compact form abbreviates the weekday")
    func compactWeekday() {
        #expect(formatter().compact(for: date(daysAgo: 1), now: now) == "Yesterday")
        #expect(formatter().compact(for: date(daysAgo: 2), now: now) == "Tue")
    }

    @Test("Older than a week shows a day and month")
    func compactOlder() {
        #expect(formatter().compact(for: date(daysAgo: 30), now: now) == "14 Jul")
    }

    @Test("An hours count never leaks across midnight into yesterday's slot")
    func compactHoursStopAtMidnight() {
        var midnightish = calendar.dateComponents([.year, .month, .day], from: now)
        midnightish.hour = 0
        midnightish.minute = 30
        let justAfterMidnight = calendar.date(from: midnightish)!

        #expect(formatter().compact(for: justAfterMidnight, now: now) == "15h")
        #expect(formatter().compact(for: justAfterMidnight.addingTimeInterval(-3_600), now: now) == "Yesterday")
    }
}
