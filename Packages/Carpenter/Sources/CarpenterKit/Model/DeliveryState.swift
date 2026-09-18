import Foundation

public enum DeliveryState: Hashable, Sendable {
    case pending

    case sent

    case noRecipients

    case delivered

    case notReported

    case displayed(at: Date)

    public var isCollected: Bool {
        switch self {
        case .pending, .sent, .noRecipients: false
        case .delivered, .notReported, .displayed: true
        }
    }

    public var wasDisplayed: Bool {
        if case .displayed = self { return true }
        return false
    }

    public var reportingIsOff: Bool { self == .notReported }

    public var isVisible: Bool { self != .pending }

    public var hasNobodyToReach: Bool { self == .noRecipients }

    public var displayedAt: Date? {
        if case .displayed(let instant) = self { return instant }
        return nil
    }
}
