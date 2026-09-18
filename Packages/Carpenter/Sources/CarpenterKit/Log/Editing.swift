import Foundation

public enum Editing {
    public static let editWindow: TimeInterval = 15 * 60

    public static let withdrawWindow: TimeInterval = 2 * 60

    public static func isOpen(
        at instant: Date, for origin: Date, within window: TimeInterval
    ) -> Bool {
        let elapsed = instant.timeIntervalSince(origin)
        return elapsed >= 0 && elapsed <= window
    }
}
