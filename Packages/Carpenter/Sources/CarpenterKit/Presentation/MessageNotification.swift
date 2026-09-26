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
    public static func thread(for room: RoomID) -> String { room.rawValue.uuidString }

    // COPY BEGIN ea951d49 [NEEDS HUMAN REVIEW]
    public static let generic = NotificationCopy(title: "New message", body: "")
    // COPY END ea951d49

    public static func of(
        room roomID: RoomID, roomName: String, author: String, body: String,
        level: NotificationLevel = .default
    ) -> NotificationCopy {
        let room = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty, !text.isEmpty else { return generic }

        guard level != .nothing else { return generic }

        let thread = level.groupsByRoom ? Self.thread(for: roomID) : ""

        // COPY BEGIN f5e2890e [NEEDS HUMAN REVIEW]
        let title = level.showsRoom && !room.isEmpty ? room : (level.showsSender ? who : "New message")
        // COPY END f5e2890e
        let subtitle = level.showsSender && level.showsRoom && !room.isEmpty ? who : ""
        let message = level.showsMessage ? text : ""

        // COPY BEGIN 7b91b3f7 [NEEDS HUMAN REVIEW]
        guard !message.isEmpty || title != "New message" || !subtitle.isEmpty else { return generic }
        // COPY END 7b91b3f7

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
        // COPY BEGIN a8ac62ea [NEEDS HUMAN REVIEW]
        let title = level.showsSender ? who : String(localized: "New post", bundle: .module)
        let subtitle = level.showsSender
            ? String(
                localized: "Posted to their Outpost", bundle: .module,
                comment: "Banner subtitle for a post on somebody's own feed")
            : ""
        // COPY END a8ac62ea
        let message = level.showsMessage ? text : ""

        guard !subtitle.isEmpty || !message.isEmpty else { return generic }
        return NotificationCopy(
            title: title, subtitle: subtitle, body: message, threadID: thread)
    }
}
