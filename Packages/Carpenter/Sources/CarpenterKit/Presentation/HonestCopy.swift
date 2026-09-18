import Foundation

public struct SyncSummary: Sendable {
    private let calendar: Calendar
    private let locale: Locale

    public init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.calendar = calendar
        self.locale = locale
    }

    public static func hasAnyoneToReach(in rooms: [RoomSummary]) -> Bool {
        rooms.contains { $0.memberCount > 1 }
    }

    public func caughtUpLine(
        peers: [String], knowsAnyone: Bool = true, at date: Date, now: Date = Date()
    ) -> String? {
        guard knowsAnyone else { return nil }
        guard !peers.isEmpty else { return nil }
        return String(
            localized: "Caught up with \(peerPhrase(peers)) \(recencyPhrase(from: date, to: now)).",
            bundle: .module, comment: "Sync footer: peers, then how long ago")
    }

    private func peerPhrase(_ peers: [String]) -> String {
        switch peers.count {
        case 1:
            return peers[0]
        case 2:
            return String(
                localized: "\(peers[0]) and \(peers[1])", bundle: .module, comment: "Two peer names")
        case 3:
            return String(
                localized: "\(peers[0]), \(peers[1]) and 1 other", bundle: .module,
                comment: "Two peer names and one more")
        default:
            return String(
                localized: "\(peers[0]), \(peers[1]) and \(peers.count - 2) others", bundle: .module,
                comment: "Two peer names and a count of the rest")
        }
    }

    private func recencyPhrase(from date: Date, to now: Date) -> String {
        let elapsed = now.timeIntervalSince(date)
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        switch days {
        case 0 where elapsed < 60:
            return String(localized: "a moment ago", bundle: .module, comment: "Sync recency")
        case 0 where elapsed < 3_600:
            let minutes = Int(elapsed / 60)
            return minutes == 1
                ? String(localized: "1 minute ago", bundle: .module, comment: "Sync recency")
                : String(localized: "\(minutes) minutes ago", bundle: .module, comment: "Sync recency")
        case 0:
            let hours = Int(elapsed / 3_600)
            return hours == 1
                ? String(localized: "1 hour ago", bundle: .module, comment: "Sync recency")
                : String(localized: "\(hours) hours ago", bundle: .module, comment: "Sync recency")
        case 1:
            return String(localized: "yesterday", bundle: .module, comment: "Sync recency")
        default:
            var style = Date.FormatStyle(date: .numeric, time: .omitted)
            style.locale = locale
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            return String(
                localized: "on \(date.formatted(style))", bundle: .module, comment: "Sync recency, dated")
        }
    }
}

public enum TagFilterSummary {
    public static func line(matching: Int, of total: Int, tagName: String) -> String {
        let count =
            matching == 0
            ? String(
                localized: "No rooms tagged \(tagName).", bundle: .module,
                comment: "Rooms list, filter matches nothing")
            : String(
                localized: "\(matching) of \(total) rooms tagged \(tagName).", bundle: .module,
                comment: "Rooms list, active tag filter")

        return count + " "
            + String(
                localized: "Tags are only on your devices — nobody in these rooms can see them.",
                bundle: .module, comment: "Rooms list, tag privacy note")
    }

    public static func managedLine(matching: Int) -> String {
        let count: String
        switch matching {
        case 0:
            count = String(
                localized: "Nothing is waiting just now.", bundle: .module,
                comment: "Rooms list, the app's own filter matches nothing")
        case 1:
            count = String(
                localized: "One join still waiting.", bundle: .module,
                comment: "Rooms list, the app's own filter is on, one room")
        default:
            count = String(
                localized: "\(matching) joins still waiting.", bundle: .module,
                comment: "Rooms list, the app's own filter is on")
        }

        return count + " "
            + String(
                localized: "Kept by the app, only on your devices, and it goes when nothing is waiting.",
                bundle: .module, comment: "Rooms list, app-managed tag note")
    }
}

public enum AudienceSummary {
    public static func line(people: Int) -> String? {
        guard people > 0 else { return nil }

        return people == 1
            ? String(
                localized: "Visible to 1 person.", bundle: .module,
                comment: "Outpost audience, one reader")
            : String(
                localized: "Visible to \(people) people.", bundle: .module,
                comment: "Outpost audience, several readers")
    }
}
