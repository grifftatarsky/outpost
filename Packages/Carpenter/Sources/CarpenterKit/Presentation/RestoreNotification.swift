import Foundation

public enum RestoreNotification {
    public static func thread(for person: ParticipantID) -> String {
        "restore.\(person.rawValue.base64EncodedString())"
    }

    public static func ofAsk(
        person: ParticipantID, name: String, roomName: String, level: NotificationLevel = .default
    ) -> NotificationCopy {
        guard level != .nothing else { return MessageNotification.generic }

        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let room = roomName.trimmingCharacters(in: .whitespacesAndNewlines)

        // COPY BEGIN c0841350 [NEEDS HUMAN REVIEW]
        let title =
            level.showsSender && !who.isEmpty
            ? String(
                localized: "\(who) set up a new device", bundle: .module,
                comment: "Banner title when somebody restores from a recovery key and asks for history")
            : String(
                localized: "Somebody set up a new device", bundle: .module,
                comment: "Banner title for a restore when the banner does not name people")
        // COPY END c0841350

        let body: String
        // COPY BEGIN f987b18d [NEEDS HUMAN REVIEW]
        if level.showsRoom && !room.isEmpty {
            body = String(
                localized: "It asked for your copy of \(room). Your history is on its way to them.",
                bundle: .module,
                comment: "Banner body naming the conversation a restored device asked for")
        } else {
            body = String(
                localized: "It asked for your copy of a conversation. Your history is on its way to them.",
                bundle: .module,
                comment: "Banner body for a restore when the banner does not name conversations")
        }
        // COPY END f987b18d

        return NotificationCopy(
            title: title, body: body,
            threadID: level.groupsByRoom ? thread(for: person) : "")
    }
}
