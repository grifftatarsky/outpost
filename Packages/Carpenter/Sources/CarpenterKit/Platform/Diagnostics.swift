import CryptoKit
import Foundation
import OSLog

public enum Diagnostics {
    public static let subsystem = "com.microgpt.carpenter"

    public static let pairing = Logger(subsystem: subsystem, category: "pairing")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let identity = Logger(subsystem: subsystem, category: "identity")

    public static func fingerprint(_ data: Data) -> String {
        guard !data.isEmpty else { return "empty" }
        return String(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(8))
    }

    public static func fingerprint(_ text: String) -> String {
        fingerprint(Data(text.utf8))
    }
}
