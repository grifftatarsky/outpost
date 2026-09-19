import CarpenterApp
import CarpenterCloudKit
import CarpenterKeychain
import CarpenterKit
import CloudKit
import Intents
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
            await self.deliver(
                rich.copy, badge: rich.badge, sender: rich.sender, quietly: rich.quietly, room: rich.room)
        }
    }

    struct Sender {
        let id: ParticipantID
        let name: String
        let image: Data?
        let roomName: String
        let isDirect: Bool
        let threadID: String
    }

    struct Rich {
        let copy: NotificationCopy
        let badge: Int?
        let sender: Sender?
        let quietly: Bool
        var room: RoomID?
    }

    override func serviceExtensionTimeWillExpire() {
        Task { await deliver(MessageNotification.generic, badge: nil, sender: nil, quietly: false, room: nil) }
    }

    private func deliver(
        _ copy: NotificationCopy, badge: Int?, sender: Sender?, quietly: Bool, room: RoomID?
    ) async {
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
            if let room {
                content.categoryIdentifier = NotificationAnswer.messageCategory
                content.userInfo.merge(NotificationAnswer.userInfo(for: room)) { _, new in new }
            }
        }
        if let badge { content.badge = NSNumber(value: badge) }

        Diagnostics.sync.notice(
            "nse: badge=\(badge.map(String.init) ?? "unchanged", privacy: .public)")
        Diagnostics.sync.notice(
            "nse: delivering \(copy.isGeneric ? "the generic banner" : "a decrypted banner", privacy: .public)")

        if quietly { content.interruptionLevel = .passive }

        var final: UNNotificationContent = content
        if !copy.isGeneric, let sender {
            let person = INPerson(
                personHandle: INPersonHandle(value: sender.id.shortCode, type: .unknown),
                nameComponents: nil, displayName: sender.name,
                image: sender.image.map { INImage(imageData: $0) },
                contactIdentifier: nil, customIdentifier: sender.id.shortCode)
            let intent = INSendMessageIntent(
                recipients: nil, outgoingMessageType: .outgoingMessageText, content: copy.body,
                speakableGroupName: sender.isDirect ? nil : INSpeakableString(spokenPhrase: sender.roomName),
                conversationIdentifier: sender.threadID, serviceName: nil, sender: person,
                attachments: nil)
            let interaction = INInteraction(intent: intent, response: nil)
            interaction.direction = .incoming
            do {
                try await interaction.donate()
                final = try content.updating(from: intent)
            } catch {
                DiagnosticsExport.note("nse: could not attach the sender (\(error))")
            }
        }

        if let url = DiagnosticsExport.groupURL { DiagnosticsExport.write(to: url, throttled: false) }

        handler(final)
    }

    @MainActor
    private static func richCopy() async -> Rich {
        let full = Bundle.main.bundleIdentifier ?? "app"
        let container = full.lastIndex(of: ".").map { String(full[..<$0]) } ?? full
        let directory = StorageLocation.directory(container: container)

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
                },
                isDirect: { [session] room in
                    MainActor.assumeIsolated { session.rooms.first { $0.id == room }?.isDirect ?? false }
                },
                authorOfMessage: { [session] room, id in
                    MainActor.assumeIsolated {
                        session.messages(in: room).first { $0.id == id }?.author
                    }
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

            let photos = PersonAvatarStore(directory: directory)
            let sender = banner.sender.map {
                Sender(
                    id: $0.id, name: $0.name,
                    image: photos.faceForABanner(from: $0.id, aboutAPost: $0.isAboutAPost),
                    roomName: $0.roomName, isDirect: $0.isDirect, threadID: $0.threadID)
            }
            return Rich(
                copy: banner.copy, badge: session.badgeNumber, sender: sender,
                quietly: banner.quietly, room: banner.room)
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
        return Rich(
            copy: MessageNotification.generic, badge: session.badgeNumber, sender: nil,
            quietly: false)
    }

    private static let attempts = 6

    private static let sharedKeychainGroup: String? = SharedKeychain.group
}
