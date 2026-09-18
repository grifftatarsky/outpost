import CarpenterKit
import UserNotifications

public enum PushPresentation {
    public static func options(
        forSubscriptionID id: String?,
        thread: String = "",
        viewing: String? = nil
    ) -> UNNotificationPresentationOptions {
        guard let channel = PushChannel.of(subscriptionID: id), channel.isVisible else { return [] }
        if !thread.isEmpty, thread == viewing { return [] }
        return [.banner, .sound, .badge]
    }
}
