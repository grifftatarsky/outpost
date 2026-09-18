import Foundation
import UserNotifications

@MainActor
public final class PushArrivals {
    public static let shared = PushArrivals()

    private var handler: (() async -> Void)?
    private var opener: ((String) -> Void)?

    public init() {}

    public func onArrival(_ handler: @escaping () async -> Void) {
        self.handler = handler
    }

    public func onOpenRoom(_ opener: @escaping (String) -> Void) {
        self.opener = opener
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
