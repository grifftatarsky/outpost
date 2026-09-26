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

        // COPY BEGIN c0841350 [HUMAN REVIEWED, UNVERIFIED]
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
        // COPY BEGIN f987b18d [HUMAN REVIEWED, UNVERIFIED]
        if level.showsRoom && !room.isEmpty {
            body = String(
                localized: "New device requested history backfill of \(room)",
                bundle: .module,
                comment: "Banner body naming the conversation a restored device asked for")
        } else {
            body = String(
                localized: "New device requested history backfill.",
                bundle: .module,
                comment: "Banner body for a restore when the banner does not name conversations")
        }
        // COPY END f987b18d

        return NotificationCopy(
            title: title, body: body,
            threadID: level.groupsByRoom ? thread(for: person) : "")
    }
}
