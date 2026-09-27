import CryptoKit
import Foundation
import Testing

@testable import CarpenterKit

@Suite("A recovery key")
struct ARecoveryKeyTests {
    private func aSecret() throws -> RecoverySecret {
        try RecoverySecret(material: Data((0..<32).map { UInt8($0) }))
    }

    @Test("A key written out reads back as the same secret, and so the same identity")
    func roundTrip() throws {
        let secret = try aSecret()
        let read = try RecoveryKey.secret(from: RecoveryKey.text(for: secret, createdAt: .distantPast))
        #expect(read == secret)
        #expect(read.identity.id == secret.identity.id)
        #expect(read.identity.signingSeed == secret.identity.signingSeed)
        #expect(read.identity.agreementSeed == secret.identity.agreementSeed)
    }

    @Test("It survives being mangled on the way")
    func survivesTheJourney() throws {
        let secret = try aSecret()
        let original = RecoveryKey.text(for: secret, createdAt: .distantPast)
        let key = try #require(
            original.split(whereSeparator: \.isNewline).first { $0.hasPrefix("KEY:") }
        ).dropFirst("KEY:".count).trimmingCharacters(in: .whitespaces)

        let mangled = [
            original.replacingOccurrences(of: "\n", with: "\r\n"),
            original.split(separator: "\n").map { "   \($0)   " }.joined(separator: "\n"),
            original.split(whereSeparator: \.isNewline).joined(separator: "\n"),
            original.lowercased(),
            key,
            key.replacingOccurrences(of: "-", with: " "),
            key.replacingOccurrences(of: "-", with: "").lowercased(),
            key.replacingOccurrences(of: "0", with: "O").replacingOccurrences(of: "1", with: "l"),
        ]

        for text in mangled {
            #expect(try RecoveryKey.secret(from: text) == secret, "a key did not survive: \(text.prefix(40))")
        }
    }

    @Test("Prose that is not a key is refused as not a key")
    func notAKey() throws {
        #expect(throws: RecoveryKey.Failure.notARecoveryKey) {
            try RecoveryKey.secret(from: "Dear Nora, here are the photos from Sunday.")
        }
        #expect(throws: RecoveryKey.Failure.notARecoveryKey) {
            try RecoveryKey.secret(from: "")
        }
    }

    @Test("A key from a newer build is refused, and says so")
    func fromTheFuture() throws {
        let ahead = RecoveryKey.text(for: try aSecret(), createdAt: .distantPast)
            .replacingOccurrences(
                of: "\(RecoveryKey.header) v\(RecoveryKey.version)",
                with: "\(RecoveryKey.header) v\(RecoveryKey.version + 7)")

        #expect(throws: RecoveryKey.Failure.fromANewerVersion(RecoveryKey.version + 7)) {
            try RecoveryKey.secret(from: ahead)
        }
    }

    @Test("A key from the old format, which held the identity itself, is refused as earlier")
    func theOldFormatIsRefused() throws {
        let old = """
            OUTPOST RECOVERY KEY v1

            SIGNING: AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=
            AGREEMENT: /////////////////////////////////////////w==
            CHECK: ABCDEFGH
            """
        #expect(throws: RecoveryKey.Failure.fromAnEarlierVersion) { try RecoveryKey.secret(from: old) }
        let unlabelled = old.replacingOccurrences(of: "OUTPOST RECOVERY KEY v1\n\n", with: "")
        #expect(throws: RecoveryKey.Failure.fromAnEarlierVersion) { try RecoveryKey.secret(from: unlabelled) }
    }

    @Test("Any single mistyped character is caught rather than restoring a stranger")
    func aMistypedCharacter() throws {
        let secret = try aSecret()
        let key = RecoveryKey.written(secret)
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        var caught = 0
        var tried = 0
        for (offset, character) in key.enumerated() where character != "-" {
            var wrong = Array(key)
            wrong[offset] = alphabet[(alphabet.firstIndex(of: character)! + 1) % alphabet.count]
            tried += 1
            do {
                _ = try RecoveryKey.secret(from: String(wrong))
            } catch RecoveryKey.Failure.damaged {
                caught += 1
            }
        }
        #expect(tried == RecoveryKey.writtenLength)
        #expect(caught == tried, "\(tried - caught) mistyped character(s) read as a valid key")
    }

    @Test("A key one character short or long is damaged, not silently another key")
    func aWrongLength() throws {
        let key = RecoveryKey.written(try aSecret())
        #expect(throws: RecoveryKey.Failure.damaged) { try RecoveryKey.secret(from: "KEY: " + key.dropLast()) }
        #expect(throws: RecoveryKey.Failure.damaged) { try RecoveryKey.secret(from: "KEY: " + key + "0") }
        #expect(throws: RecoveryKey.Failure.damaged) {
            try RecoveryKey.secret(from: "\(RecoveryKey.header) v\(RecoveryKey.version)\n\nno key here")
        }
    }

    @Test("The fingerprint on the file is the one the app shows")
    func theFingerprintMatches() throws {
        let secret = try aSecret()
        let text = RecoveryKey.text(for: secret, createdAt: .distantPast)
        #expect(text.contains(secret.identity.id.shortCode))
        #expect(RecoveryKey.fingerprint(of: secret.identity) == secret.identity.id.shortCode)
    }

    @Test("The file carries the key and nothing the identity is made of")
    func carriesOnlyTheKey() throws {
        let secret = try aSecret()
        let text = RecoveryKey.text(for: secret, createdAt: .distantPast)

        let labels = text.split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                guard let colon = line.firstIndex(of: ":") else { return nil }
                let label = String(line[line.startIndex..<colon])
                return label.allSatisfy { $0.isUppercase || $0.isLetter } ? label : nil
            }
            .filter { $0 == $0.uppercased() }
        #expect(Set(labels) == ["KEY"], "a recovery key grew a field: \(labels)")

        let identity = secret.identity
        for seed in [identity.signingSeed, identity.agreementSeed] {
            #expect(!text.contains(seed.base64EncodedString()))
            #expect(!text.contains(Base32.encode(seed)))
        }
    }
}

@Suite("The recovery key is its own key, and the identity alone cannot stand in for it")
struct TheRecoveryKeyIsItsOwnKeyTests {
    @Test("Every derived key is distinct, and nothing a device holds gives back the recovery key")
    func derivedKeysAreSeparate() throws {
        let secret = RecoverySecret.generate()
        let identity = secret.identity
        let keys = [identity.signingSeed, identity.agreementSeed, secret.seed("recovery-authority"), secret.material]
        #expect(Set(keys).count == keys.count)
        #expect(identity.publicKeys.recovery == secret.publicKey)
        #expect(identity.publicKeys.recovery != identity.publicKeys.signing)

        let held = identity.withoutRecovery
        #expect(held.recovery == nil)
        #expect(held == identity, "the identity a device keeps is the same person")
        #expect(throws: CryptoError.notAuthorized) {
            try DeviceCertificate.recovered(for: DeviceKeys.generate(), by: held, at: .now)
        }
    }

    @Test("The identity's name commits to its recovery key, so another recovery key is another person")
    func theNameCommitsToTheRecoveryKey() throws {
        let identity = RecoverySecret.generate().identity
        let swapped = IdentityPublicKeys(
            signing: identity.publicKeys.signing, agreement: identity.publicKeys.agreement,
            recovery: RecoverySecret.generate().publicKey)
        #expect(swapped.participantID != identity.id)
    }

    @Test("A recovery signature from another recovery key is refused")
    func anotherRecoveryKeyIsRefused() throws {
        let real = RecoverySecret.generate().identity
        let forged = try Identity(
            signingSeed: real.signingSeed, agreementSeed: real.agreementSeed,
            recovery: RecoverySecret.generate())
        let certificate = try DeviceCertificate.recovered(for: DeviceKeys.generate(), by: forged, at: .now)
        var relabelled = certificate
        relabelled.participant = real.id
        relabelled.signature = try real.sign(relabelled.signingPayload)

        #expect(throws: CryptoError.self) { try relabelled.verify(against: real.publicKeys) }
        #expect(throws: CryptoError.self) { try certificate.verify(against: real.publicKeys) }
    }

    @Test("A certificate cannot be both approved and recovered")
    func notBoth() throws {
        let identity = Identity.generate()
        let approver = DeviceKeys.generate()
        var certificate = try DeviceCertificate.recovered(for: DeviceKeys.generate(), by: identity, at: .now)
        certificate.approvedBy = approver.id
        certificate.approval = try approver.sign(certificate.signingPayload)
        certificate.signature = try identity.sign(certificate.signingPayload)
        certificate.recoverySignature = try identity.recovery!.sign(certificate.signingPayload)
        #expect(throws: CryptoError.badSignature) { try certificate.verify(against: identity.publicKeys) }
    }
}
