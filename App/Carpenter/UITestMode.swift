import CarpenterKit
import Foundation

#if DEBUG
    enum UITestMode {
        static let argument = "--quiet-for-audit"

        static let isOn = ProcessInfo.processInfo.arguments.contains(argument)

        static var clock: any Clock {
            let arguments = ProcessInfo.processInfo.arguments
            guard let flag = arguments.firstIndex(of: "--clock-ahead-days"),
                arguments.indices.contains(flag + 1),
                let days = Double(arguments[flag + 1])
            else { return SystemClock() }
            return AheadClock(by: days * 86_400)
        }
    }

    private struct AheadClock: Clock {
        let interval: TimeInterval

        init(by interval: TimeInterval) { self.interval = interval }

        var now: Date { Date().addingTimeInterval(interval) }
    }
#else
    enum UITestMode {
        static let isOn = false

        static var clock: any Clock { SystemClock() }
    }
#endif
