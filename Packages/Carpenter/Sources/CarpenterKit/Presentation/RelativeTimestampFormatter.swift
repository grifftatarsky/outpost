import Foundation

public struct RelativeTimestampFormatter: Sendable {
    private let calendar: Calendar
    private let locale: Locale

    public init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.calendar = calendar
        self.locale = locale
    }

    // COPY BEGIN 0b1bac5f [NEEDS HUMAN REVIEW]
    public func roomsList(for date: Date, now: Date = Date()) -> String {
        switch elapsedDays(from: date, to: now) {
        case 0: format(date, .dateTime.hour().minute())
        case 1: String(localized: "Yesterday", bundle: .module, comment: "Rooms list timestamp")
        case 2..<7: format(date, .dateTime.weekday(.wide))
        default: format(date, Date.FormatStyle(date: .numeric, time: .omitted))
        }
    }
    // COPY END 0b1bac5f

    public func compact(for date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)

        switch elapsedDays(from: date, to: now) {
        case 0 where elapsed < 60:
            // COPY BEGIN c25433ef [NEEDS HUMAN REVIEW]
            return String(localized: "now", bundle: .module, comment: "Outpost timestamp, under a minute old")
        case 0 where elapsed < 3_600:
            return String(
                localized: "\(Int(elapsed / 60))m", bundle: .module, comment: "Outpost timestamp in minutes")
        case 0:
            return String(
                localized: "\(Int(elapsed / 3_600))h", bundle: .module, comment: "Outpost timestamp in hours")
        case 1:
            return String(localized: "Yesterday", bundle: .module, comment: "Rooms list timestamp")
            // COPY END c25433ef
        case 2..<7:
            return format(date, .dateTime.weekday(.abbreviated))
        default:
            return format(date, .dateTime.day().month(.abbreviated))
        }
    }

    // COPY BEGIN afbe82eb [NEEDS HUMAN REVIEW]
    public func readReceipt(_ date: Date, now: Date = Date()) -> String {
        switch elapsedDays(from: date, to: now) {
        case 0:
            return format(date, .dateTime.hour().minute())
        case 1:
            return String(
                localized: "Yesterday", bundle: .module, comment: "Read receipt, the previous day")
        default:
            return format(date, .dateTime.day().month(.abbreviated))
        }
    }
    // COPY END afbe82eb

    private func elapsedDays(from date: Date, to now: Date) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private func format(_ date: Date, _ style: Date.FormatStyle) -> String {
        var style = style
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
