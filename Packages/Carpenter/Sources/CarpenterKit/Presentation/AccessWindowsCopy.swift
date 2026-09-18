import Foundation

public enum AccessWindowsCopy {
    public static func lines(for windows: [AccessWindow]) -> [String] {
        windows.map(line(for:))
    }

    public static func line(for window: AccessWindow) -> String {
        switch (window.from, window.until) {
        case (nil, nil):
            return String(
                localized: "Everything", bundle: .module,
                comment: "Outpost access: the whole wall, still growing")
        case (nil, let until?):
            return String(
                localized: "Everything up to \(date(until))", bundle: .module,
                comment: "Outpost access: the whole wall, up to a date")
        case (let from?, nil):
            return String(
                localized: "\(date(from)) – present", bundle: .module,
                comment: "Outpost access: a stretch that is still growing")
        case (let from?, let until?):
            return String(
                localized: "\(date(from)) – \(date(until))", bundle: .module,
                comment: "Outpost access: a stretch that has ended")
        }
    }

    public static func summary(for windows: [AccessWindow]) -> String {
        guard let newest = windows.last else {
            return String(
                localized: "No access", bundle: .module,
                comment: "Outpost access: nothing, and nothing before")
        }
        let head = line(for: newest)
        let earlier = windows.count - 1
        guard earlier > 0 else { return head }
        return earlier == 1
            ? String(
                localized: "\(head), and 1 earlier stretch", bundle: .module,
                comment: "Outpost access: the newest stretch, and the one behind it")
            : String(
                localized: "\(head), and \(earlier) earlier stretches", bundle: .module,
                comment: "Outpost access: the newest stretch, and how many are behind it")
    }

    private static func date(_ moment: Date) -> String {
        moment.formatted(date: .numeric, time: .omitted)
    }
}
