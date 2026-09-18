import Foundation
import OSLog
import Synchronization

public enum DiagnosticsExport {
    public static let fileName = "diagnostics.log"

    public static let extensionFileName = "diagnostics-extension.log"

    public static func write(
        to url: URL, window: TimeInterval = 30 * 60, throttled: Bool = true
    ) {
        let now = Date()
        let skip = !throttled ? false : lastWritten.withLock { last -> Bool in
            guard now.timeIntervalSince(last) < minimumInterval else {
                last = now
                return false
            }
            return true
        }
        if skip { return }

        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return }
        let start = store.position(date: Date(timeIntervalSinceNow: -window))
        let predicate = NSPredicate(format: "subsystem == %@", Diagnostics.subsystem)
        guard let entries = try? store.getEntries(at: start, matching: predicate) else { return }

        var lines: [String] = []
        for case let entry as OSLogEntryLog in entries {
            lines.append("\(entry.date.ISO8601Format()) [\(entry.category)] \(entry.composedMessage)")
        }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let minimumInterval: TimeInterval = 30
    private static let lastWritten = Mutex(Date.distantPast)

    public static var documentsURL: URL? {
        try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: fileName)
    }

    public static func note(_ line: String) {
        guard let url = groupURL else { return }
        let stamped = "\(Date().ISO8601Format()) \(line)\n"
        guard let data = stamped.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    public static var groupURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appending(path: extensionFileName)
    }
}
