import Foundation

public enum DebugDelayFormatter {
    public static func text(_ seconds: TimeInterval) -> String {
        if abs(seconds) < 1 { return String(format: "%.0f ms", seconds * 1000) }
        if abs(seconds) < 60 { return String(format: "%.1f s", seconds) }
        return String(format: "%.0f m %.0f s", (seconds / 60).rounded(.towardZero), abs(seconds.truncatingRemainder(dividingBy: 60)))
    }
}
