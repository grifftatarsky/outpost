import Foundation

enum TestDeadline {
    static let seconds: TimeInterval = 60

    static var fromNow: Date { Date().addingTimeInterval(seconds) }
}
