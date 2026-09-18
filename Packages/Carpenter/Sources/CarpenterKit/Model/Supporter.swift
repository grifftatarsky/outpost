import Foundation

public enum DistributionChannel: String, Hashable, Sendable {
    case testFlight, appStore, development

    public var offersTheTestFlightYear: Bool { self != .appStore }
}

public enum SupporterStanding: Hashable, Sendable {
    case none
    case testFlightYear(endsAt: Date?)

    public var isSupporter: Bool { self != .none }

    public static let yearLength: DateComponents = DateComponents(year: 1)

    public static func of(
        claimedAt: Date?, startedAt: Date?, channel: DistributionChannel, now: Date
    ) -> SupporterStanding {
        guard claimedAt != nil else { return .none }
        let start = startedAt ?? (channel == .appStore ? now : nil)
        guard let start else { return .testFlightYear(endsAt: nil) }
        guard let end = yearEnd(from: start) else { return .none }
        return now < end ? .testFlightYear(endsAt: end) : .none
    }

    static func yearEnd(from start: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return calendar.date(byAdding: yearLength, to: start)
    }
}
