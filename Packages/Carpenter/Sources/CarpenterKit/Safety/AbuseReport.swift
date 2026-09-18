import Foundation

public struct AbuseReport: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case text
        case photo
    }

    public let description: String
    public let sender: ParticipantID
    public let senderName: String?
    public let entry: EntryHash
    public let sentAt: Date
    public let kind: Kind
    public let reportedAt: Date
    public let appVersion: String

    public init(
        description: String,
        sender: ParticipantID,
        senderName: String?,
        entry: EntryHash,
        sentAt: Date,
        kind: Kind,
        reportedAt: Date,
        appVersion: String
    ) {
        self.description = description
        self.sender = sender
        self.senderName = senderName
        self.entry = entry
        self.sentAt = sentAt
        self.kind = kind
        self.reportedAt = reportedAt
        self.appVersion = appVersion
    }

    public var senderFingerprint: String { DenyList.fingerprint(of: sender) }

    public var messageID: String {
        entry.rawValue.map { String(format: "%02x", $0) }.joined()
    }


    public var body: String {
        let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        var lines: [String] = []
        lines.append("What happened:")
        lines.append(description.trimmingCharacters(in: .whitespacesAndNewlines))
        lines.append("")
        lines.append("Reported: \(kind == .photo ? "a photo" : "a text message")")
        lines.append("Sender fingerprint (SHA-256 of their identifier): \(senderFingerprint)")
        lines.append("Sender short code: \(sender.shortCode)")
        if let senderName, !senderName.isEmpty {
            lines.append("Sender's display name, as shown (chosen by them, unverified): \(senderName)")
        }
        lines.append("Message ID (entry hash): \(messageID)")
        lines.append("Sent at: \(sentAt.formatted(stamp)) (UTC)")
        lines.append("Reported at: \(reportedAt.formatted(stamp)) (UTC)")
        lines.append("App version: \(appVersion)")
        lines.append("")
        lines.append(
            "This report carries no message content and no media. The app cannot attach them: "
                + "messages are end-to-end encrypted and the developer holds no key.")
        return lines.joined(separator: "\n")
    }

}
