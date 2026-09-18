import CryptoKit
import Foundation
import Testing

@testable import CarpenterKit

@Suite("A recovery key")
struct ARecoveryKeyTests {
    private func anIdentity() throws -> Identity {
        try Identity(
            signingSeed: Data((0..<32).map { UInt8($0) }),
            agreementSeed: Data((0..<32).map { UInt8(255 - $0) }))
    }

    @Test("A key written out reads back as the same identity")
    func roundTrip() throws {
        let identity = try anIdentity()
        let read = try RecoveryKey.identity(
            from: RecoveryKey.text(for: identity, createdAt: .distantPast))
        #expect(read.id == identity.id)
        #expect(read.signingSeed == identity.signingSeed)
        #expect(read.agreementSeed == identity.agreementSeed)
    }

    @Test("It survives being mangled on the way")
    func survivesTheJourney() throws {
        let identity = try anIdentity()
        let original = RecoveryKey.text(for: identity, createdAt: .distantPast)

        let mangled = [
            original.replacingOccurrences(of: "\n", with: "\r\n"),
            original.split(separator: "\n").map { "   \($0)   " }.joined(separator: "\n"),
            original.split(whereSeparator: \.isNewline).joined(separator: "\n"),
            original.replacingOccurrences(of: "\n", with: "\r\n")
                .split(whereSeparator: \.isNewline).map { "  \($0)" }.joined(separator: "\r\n"),
        ]

        for text in mangled {
            let read = try RecoveryKey.identity(from: text)
            #expect(read.id == identity.id, "a key did not survive an ordinary reformatting")
        }
    }

    @Test("Prose that is not a key is refused as not a key")
    func notAKey() throws {
        #expect(throws: RecoveryKey.Failure.notARecoveryKey) {
            try RecoveryKey.identity(from: "Dear Nora, here are the photos from Sunday.")
        }
        #expect(throws: RecoveryKey.Failure.notARecoveryKey) {
            try RecoveryKey.identity(from: "")
        }
    }

    @Test("A key from a newer build is refused, and says so")
    func fromTheFuture() throws {
        let identity = try anIdentity()
        let ahead = RecoveryKey.text(for: identity, createdAt: .distantPast)
            .replacingOccurrences(
                of: "\(RecoveryKey.header) v\(RecoveryKey.version)",
                with: "\(RecoveryKey.header) v\(RecoveryKey.version + 7)")

        #expect(throws: RecoveryKey.Failure.fromANewerVersion(RecoveryKey.version + 7)) {
            try RecoveryKey.identity(from: ahead)
        }
    }

    @Test("A mistyped seed is caught rather than restoring a stranger")
    func aMistypedSeed() throws {
        let identity = try anIdentity()
        let text = RecoveryKey.text(for: identity, createdAt: .distantPast)

        let seed = identity.signingSeed.base64EncodedString()
        var wrong = Array(seed)
        wrong[4] = wrong[4] == "A" ? "B" : "A"

        let mistyped = text.replacingOccurrences(of: seed, with: String(wrong))
        #expect(throws: RecoveryKey.Failure.damaged) {
            try RecoveryKey.identity(from: mistyped)
        }
    }

    @Test("A key with a line missing is damaged, not silently short")
    func aMissingLine() throws {
        let identity = try anIdentity()
        let text = RecoveryKey.text(for: identity, createdAt: .distantPast)
        let without = text.split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("AGREEMENT:") }
            .joined(separator: "\n")

        #expect(throws: RecoveryKey.Failure.damaged) {
            try RecoveryKey.identity(from: without)
        }
    }

    @Test("The fingerprint on the file is the one the app shows")
    func theFingerprintMatches() throws {
        let identity = try anIdentity()
        let text = RecoveryKey.text(for: identity, createdAt: .distantPast)
        #expect(text.contains(identity.id.shortCode))
        #expect(RecoveryKey.fingerprint(of: identity) == identity.id.shortCode)
    }

    @Test("A key carries the two seeds and nothing that belongs to anybody else")
    func carriesOnlyTheSeeds() throws {
        let identity = try anIdentity()
        let text = RecoveryKey.text(for: identity, createdAt: .distantPast)

        let labels = text.split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                guard let colon = line.firstIndex(of: ":") else { return nil }
                let label = String(line[line.startIndex..<colon])
                return label.allSatisfy { $0.isUppercase || $0.isLetter } ? label : nil
            }
            .filter { $0 == $0.uppercased() }

        #expect(
            Set(labels) == ["SIGNING", "AGREEMENT", "CHECK"],
            "a recovery key grew a field: \(labels). It may carry the two seeds and the check, and nothing else")
    }
}
