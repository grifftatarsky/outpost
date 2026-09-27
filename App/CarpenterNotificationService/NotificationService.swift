import CarpenterApp
import CarpenterCloudKit
import CarpenterKeychain
import CarpenterKit
import CloudKit
import OSLog
import UserNotifications

final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        lock.withLock {
            self.contentHandler = contentHandler
            bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent
        }

        Diagnostics.sync.notice(
            """
            nse: woke for subscription \
            \(CKNotification(fromRemoteNotificationDictionary: request.content.userInfo)?
                .subscriptionID ?? "unknown", privacy: .public)
            """)

        Task {
            let rich = await NotificationService.richCopy()
            if await NotificationService.appIsLocked() {
                DiagnosticsExport.note("nse: the app lock is on; delivering the generic banner")
                await self.deliver(MessageNotification.generic, badge: rich.badge, quietly: rich.quietly)
            } else {
                await self.deliver(rich.copy, badge: rich.badge, quietly: rich.quietly)
            }
        }
    }

    struct Rich {
        let copy: NotificationCopy
        let badge: Int?
        let quietly: Bool
    }

    override func serviceExtensionTimeWillExpire() {
        Task { await deliver(MessageNotification.generic, badge: nil, quietly: false) }
    }

    private func deliver(_ copy: NotificationCopy, badge: Int?, quietly: Bool) async {
        let taken: ((UNNotificationContent) -> Void, UNMutableNotificationContent)? = lock.withLock {
            guard let handler = contentHandler, let content = bestAttempt else { return nil }
            contentHandler = nil
            return (handler, content)
        }
        guard let (handler, content) = taken else { return }

        if !copy.isGeneric {
            content.title = copy.title
            content.subtitle = copy.subtitle
            content.body = copy.body
            content.threadIdentifier = copy.threadID
        }
        if let badge { content.badge = NSNumber(value: badge) }

        Diagnostics.sync.notice(
            "nse: badge=\(badge.map(String.init) ?? "unchanged", privacy: .public)")
        Diagnostics.sync.notice(
            "nse: delivering \(copy.isGeneric ? "the generic banner" : "a decrypted banner", privacy: .public)")

        if quietly { content.interruptionLevel = .passive }

        if let url = DiagnosticsExport.groupURL { DiagnosticsExport.write(to: url, throttled: false) }

        handler(content)
    }

    @MainActor
    private static func richCopy() async -> Rich {
        let full = Bundle.main.bundleIdentifier ?? "app"
        let container = full.lastIndex(of: ".").map { String(full[..<$0]) } ?? full
        let directory = StorageLocation.directory(container: container)

        #if DEBUG
            if TestProfileStore(directory: directory).isAnyProfileActive {
                DiagnosticsExport.note("nse: a test profile is on; iCloud stays closed")
                return Rich(copy: MessageNotification.generic, badge: nil, quietly: true)
            }
        #endif

        let storage = SessionStorage(
            keychain: SystemKeychainStore(service: container, accessGroup: sharedKeychainGroup),
            log: FileLogStore(url: directory.appending(path: StorageLocation.logName)),
            documents: FileDocumentStore(url: directory.appending(path: StorageLocation.stateName))
        ).readOnly

        DiagnosticsExport.note(
            "nse: storage=\(directory.path) appGroup=\(AppGroup.available ? "yes" : "NO — private container")")

        let session = AppSession(storage: storage)
        await session.load()

        let before = session.latestIncomingMessage()?.id
        let beforePost = session.latestIncomingPost()?.id
        let beforeRestore = session.latestRestoreAsk()?.request

        @MainActor func whatArrived(_ attempt: Int) -> Rich? {
            let world = WhatArrived.Surroundings(
                filter: FocusFilterStore.shared.read(),
                defaultLevel: session.notificationLevel,
                levelForRoom: { [session] room in
                    MainActor.assumeIsolated { session.notificationLevel(for: room) }
                })

            guard
                let banner = WhatArrived.since(
                    BannerSnapshot(post: beforePost, ask: beforeRestore, message: before),
                    post: session.latestIncomingPost(),
                    ask: session.latestRestoreAsk(),
                    message: session.latestIncomingMessage(),
                    in: world)
            else { return nil }

            DiagnosticsExport.note("nse: found something new after \(attempt + 1) attempt(s)")

            return Rich(copy: banner.copy, badge: session.badgeNumber, quietly: banner.quietly)
        }

        for attempt in 0..<Self.attempts {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(400)) }

            guard
                (try? await session.sync(
                    through: CloudKitMailbox(container: .default()), mode: .readOnly)) != nil
            else { continue }

            if let rich = whatArrived(attempt) { return rich }

            await session.load()
            if let rich = whatArrived(attempt) { return rich }
        }

        DiagnosticsExport.note("nse: nothing new became visible; delivering the generic banner")
        return Rich(copy: MessageNotification.generic, badge: session.badgeNumber, quietly: false)
    }

    private static let attempts = 6

    private static func appIsLocked() async -> Bool {
        let full = Bundle.main.bundleIdentifier ?? "app"
        let container = full.lastIndex(of: ".").map { String(full[..<$0]) } ?? full
        let store = AppLockStore(
            keychain: SystemKeychainStore(service: container, accessGroup: sharedKeychainGroup))
        do {
            return try await store.load() != nil
        } catch {
            return true
        }
    }

    private static let sharedKeychainGroup: String? = SharedKeychain.group
}
