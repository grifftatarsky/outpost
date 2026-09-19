import CarpenterKit
import Foundation
import UserNotifications

public enum NotificationAnswer: Equatable, Sendable {
    case open
    case nothing
    case reply(RoomID, String)
    case markRead(RoomID)

    public static let messageCategory = "outpost.message"
    public static let replyAction = "outpost.reply"
    public static let markReadAction = "outpost.mark-read"
    public static let roomKey = "outpost.room"

    public static func userInfo(for room: RoomID) -> [String: String] {
        [roomKey: room.rawValue.uuidString]
    }

    public static func from(action: String, userInfo: [AnyHashable: Any], text: String?) -> NotificationAnswer {
        guard action == replyAction || action == markReadAction else { return .open }
        guard let raw = userInfo[roomKey] as? String, let id = UUID(uuidString: raw) else { return .nothing }
        let room = RoomID(rawValue: id)
        guard action == replyAction else { return .markRead(room) }
        let words = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return words.isEmpty ? .nothing : .reply(room, words)
    }

    public static var categories: Set<UNNotificationCategory> {
        let reply = UNTextInputNotificationAction(
            identifier: replyAction,
            title: String(localized: "Reply", bundle: .module),
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left"),
            textInputButtonTitle: String(localized: "Send", bundle: .module),
            textInputPlaceholder: String(localized: "Message", bundle: .module))
        let read = UNNotificationAction(
            identifier: markReadAction,
            title: String(localized: "Mark as Read", bundle: .module),
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        return [
            UNNotificationCategory(
                identifier: messageCategory, actions: [reply, read], intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: String(localized: "Message", bundle: .module), options: [])
        ]
    }
}

extension AppSession {
    public func answer(_ answer: NotificationAnswer) async throws {
        switch answer {
        case .reply(let room, let words):
            try await send(words, to: room)
            await markRoomRead(room)
        case .markRead(let room):
            await markRoomRead(room)
        case .open, .nothing:
            break
        }
    }
}

extension NotificationAnswer {
    public var kind: String {
        switch self {
        case .open: "open"
        case .nothing: "nothing"
        case .reply: "reply"
        case .markRead: "mark read"
        }
    }
}

extension NotificationAnswer {
    public static func notSent(
        _ words: String, in room: RoomID, named name: String?, showingWords: Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = name ?? String(localized: "Your reply", bundle: .module)
        content.body =
            showingWords
            ? String(localized: "Not sent: “\(words)”. Open the conversation to send it again.", bundle: .module)
            : String(localized: "Your reply was not sent. Open the conversation to send it again.", bundle: .module)
        content.threadIdentifier = MessageNotification.thread(for: room)
        content.userInfo = userInfo(for: room)
        return content
    }
}
