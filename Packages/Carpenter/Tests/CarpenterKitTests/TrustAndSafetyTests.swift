@testable import CarpenterKit
import Foundation
import Testing
import CarpenterKitTesting

@Suite("Reporting a message")
struct AbuseReportTests {
    private let sender = ParticipantID(rawValue: WideID.of([0xAB, 0xCD, 0xEF, 1, 2, 3]))
    private let entry = EntryHash(rawValue: Data([9, 8, 7, 6]))

    private func report(description: String = "A photo I did not want.") -> AbuseReport {
        AbuseReport(
            description: description, sender: sender, senderName: "Nora", entry: entry,
            sentAt: Date(timeIntervalSince1970: 1_786_635_000),
            kind: .photo, reportedAt: Date(timeIntervalSince1970: 1_786_640_000),
            appVersion: "1.0 (7)")
    }

    @Test("The body names the sender by hash, the message by hash, and the times in UTC")
    func bodyCarriesTheFacts() {
        let body = report().body
        #expect(body.contains(DenyList.fingerprint(of: sender)))
        #expect(body.contains("09080706"), "the entry hash is the message ID")
        #expect(body.contains("A photo I did not want."))
        #expect(body.contains("(UTC)"))
        #expect(body.contains("1.0 (7)"))
        #expect(body.contains("no message content and no media"))
    }

    @Test("The body keeps the shape the report form verifies")
    func bodyMatchesWhatTheFormParses() throws {
        let body = report().body
        let lines = body.components(separatedBy: "\n")

        #expect(lines.first == "What happened:", "the form reads the description from this heading")

        func line(startingWith prefix: String) throws -> String {
            let found = lines.filter { $0.hasPrefix(prefix) }
            #expect(found.count == 1, "\(prefix) appears \(found.count) times; the form accepts exactly one")
            return String(try #require(found.first).dropFirst(prefix.count))
        }

        let kind = try line(startingWith: "Reported: ")
        #expect(kind == "a photo" || kind == "a text message")

        let fingerprint = try line(startingWith: "Sender fingerprint (SHA-256 of their identifier): ")
        #expect(fingerprint.count == 64)
        #expect(fingerprint.allSatisfy { $0.isHexDigit && !$0.isUppercase })

        let shortCode = try line(startingWith: "Sender short code: ")
        #expect(shortCode.count == 6)
        #expect(shortCode.allSatisfy { $0.isHexDigit && !$0.isLowercase })

        let messageID = try line(startingWith: "Message ID (entry hash): ")
        #expect(messageID.allSatisfy { $0.isHexDigit && !$0.isUppercase })

        for label in ["Sent at: ", "Reported at: "] {
            let stamp = try line(startingWith: label)
            #expect(stamp.hasSuffix(" (UTC)"))
            let value = String(stamp.dropLast(" (UTC)".count))
            let parsed = try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(value)
            #expect(parsed != nil, "\(label)\(value) is not an ISO-8601 instant the form can read")
        }

        #expect(!(try line(startingWith: "App version: ")).isEmpty)
        #expect(body.contains("This report carries no message content and no media."))
    }

    @Test("A report is text a strict decoder accepts, because the form refuses anything else")
    func bodyIsPlainText() {
        let body = report(description: "Line one.\n\nLine two, with an em dash — and a quote \u{201C}here\u{201D}.").body
        #expect(body.data(using: .utf8) != nil)
        for character in body.unicodeScalars where character.properties.generalCategory == .control {
            #expect(
                character == "\n" || character == "\r" || character == "\t",
                "the report carries a control character the form refuses")
        }
    }

    @Test("A report has no field for media, and says so")
    func noRoomForMedia() throws {
        let mirror = Mirror(reflecting: report())
        for child in mirror.children {
            #expect(!(child.value is Data), "a report grew a bytes field: \(child.label ?? "?")")
        }
        #expect(report().body.contains("cannot attach them"))
    }

    @Test("A report is small enough to paste, since pasting is how it travels")
    func fitsOnAClipboard() {
        #expect(report().body.utf8.count < 4096)
    }
}

@Suite("The deny list")
struct DenyListTests {
    private let person = ParticipantID(rawValue: WideID.of([1, 2, 3]))

    @Test("Loads from its file and matches by hash, whatever the case")
    func parses() throws {
        let hash = DenyList.fingerprint(of: person)
        let file = """
            {"version": 3, "updated": "2026-09-04", "fingerprints": ["\(hash.uppercased())"]}
            """
        let list = try DenyList(data: Data(file.utf8))
        #expect(list.version == 3)
        #expect(list.updated == "2026-09-04")
        #expect(list.contains(person))
        #expect(!list.contains(ParticipantID(rawValue: WideID.of([4]))))
    }

    @Test("A fingerprint is the full SHA-256, as hex")
    func fingerprintShape() {
        let hash = DenyList.fingerprint(of: person)
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit })
        #expect(hash == hash.lowercased())
    }

    @Test("The bundled list loads")
    func bundledLoads() {
        let list = DenyList.bundled()
        #expect(list.version >= 1, "the resource is missing from the bundle")
        #expect(!list.updated.isEmpty)
    }

    @Test("Empty names nobody")
    func emptyNamesNobody() {
        #expect(!DenyList.empty.contains(person))
    }
}

@Suite("The date on the deny list")
struct DenyListDateTests {
    @Test("The bundled list carries a real date, in a form the copy can print")
    func theBundledDateIsReal() throws {
        let list = DenyList.bundled()

        #expect(
            !list.updated.isEmpty,
            """
            The Safety footer says the list was "last changed <date>". An empty date prints an empty \
            sentence, which reads as a bug rather than as an unknown.
            """)

        let parts = list.updated.split(separator: "-")
        #expect(parts.count == 3, "the date should be ISO 8601, so it sorts and reads the same everywhere")
        #expect(parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2)
        #expect(parts.allSatisfy { $0.allSatisfy(\.isNumber) })
    }

    @Test("An empty list is still a list, and says so with a date rather than a silence")
    func anEmptyListStillHasADate() throws {
        let list = DenyList.bundled()
        if list.fingerprints.isEmpty {
            #expect(!list.updated.isEmpty, "an empty list still has to say when it was last looked at")
        }
    }
}
