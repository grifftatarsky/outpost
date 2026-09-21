import Foundation

public struct NotificationCopy: Hashable, Sendable {
    public let title: String
    public let subtitle: String
    public let body: String

    public let threadID: String

    public var isGeneric: Bool { self == MessageNotification.generic }

    public init(title: String, subtitle: String = "", body: String, threadID: String = "") {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.threadID = threadID
    }
}

public enum MessageNotification {
    public static func thread(for room: ConversationID) -> String { room.stableName }

    public static let generic = NotificationCopy(title: "New message", body: "")

    public static func of(
        room roomID: ConversationID, roomName: String, author: String, body: String,
        level: NotificationLevel = .default
    ) -> NotificationCopy {
        let room = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty, !text.isEmpty else { return generic }

        guard level != .nothing else { return generic }

        let thread = level.groupsByRoom ? Self.thread(for: roomID) : ""

        let title = level.showsRoom && !room.isEmpty ? room : (level.showsSender ? who : "New message")
        let subtitle = level.showsSender && level.showsRoom && !room.isEmpty ? who : ""
        let message = level.showsMessage ? text : ""

        guard !message.isEmpty || title != "New message" || !subtitle.isEmpty else { return generic }

        return NotificationCopy(
            title: title, subtitle: subtitle, body: message, threadID: thread)
    }

    public static func outpostThread(for author: ParticipantID) -> String {
        "outpost.\(author.rawValue.base64EncodedString())"
    }

    public static func ofPost(
        author: ParticipantID, name: String, body: String, level: NotificationLevel = .default
    ) -> NotificationCopy {
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty, level != .nothing else { return generic }

        let thread = level.groupsByRoom ? outpostThread(for: author) : ""
        let title = level.showsSender ? who : String(localized: "New post", bundle: .module)
        let subtitle = level.showsSender
            ? String(
                localized: "Posted to their Outpost", bundle: .module,
                comment: "Banner subtitle for a post on somebody's own feed")
            : ""
        let message = level.showsMessage ? text : ""

        guard !subtitle.isEmpty || !message.isEmpty else { return generic }
        return NotificationCopy(
            title: title, subtitle: subtitle, body: message, threadID: thread)
    }
}
