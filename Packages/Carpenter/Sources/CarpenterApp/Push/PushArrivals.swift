import Foundation
import UserNotifications

@MainActor
public final class PushArrivals {
    public static let shared = PushArrivals()

    private var handler: (() async -> Void)?
    private var opener: ((String) -> Void)?
    private var answerer: ((NotificationAnswer) async -> Void)?

    public init() {}

    public func onArrival(_ handler: @escaping () async -> Void) {
        self.handler = handler
    }

    public func onOpenRoom(_ opener: @escaping (String) -> Void) {
        self.opener = opener
    }

    public func onAnswer(_ answerer: @escaping (NotificationAnswer) async -> Void) {
        self.answerer = answerer
    }

    public func answer(_ answer: NotificationAnswer) async -> Bool {
        guard let answerer else { return false }
        await answerer(answer)
        return true
    }

    public func open(thread: String) {
        guard !thread.isEmpty else { return }
        opener?(thread)
    }

    public func arrived() async {
        await handler?()
    }

    public var isListening: Bool { handler != nil }
}
