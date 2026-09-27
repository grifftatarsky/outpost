import CryptoKit
import Foundation

public struct RecoverySecret: Hashable, Sendable {
    public static let byteCount = 32

    public let material: Data

    public init(material: Data) throws {
        guard material.count == Self.byteCount else { throw CryptoError.malformedKey }
        self.material = material
    }

    public static func generate() -> RecoverySecret {
        try! RecoverySecret(material: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }

    func seed(_ purpose: String) -> Data {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: material),
            salt: Data(Domain.recoverySecret.utf8),
            info: CanonicalBytes.payload(domain: Domain.recoverySecret, fields: [Data(purpose.utf8)]),
            outputByteCount: 32
        ).withUnsafeBytes { Data($0) }
    }

    private var signingKey: Curve25519.Signing.PrivateKey {
        try! Curve25519.Signing.PrivateKey(rawRepresentation: seed("recovery-authority"))
    }

    public var publicKey: Data { signingKey.publicKey.rawRepresentation }

    public func sign(_ message: Data) throws -> Data {
        try signingKey.signature(for: message)
    }

    public var identity: Identity {
        try! Identity(
            signingSeed: seed("identity-signing"), agreementSeed: seed("identity-agreement"), recovery: self)
    }
}

public enum RecoveryKey {
    public static let header = "OUTPOST RECOVERY KEY"

    public static let version = 2

    public enum Failure: Error, Equatable {
        case notARecoveryKey
        case fromANewerVersion(Int)
        case fromAnEarlierVersion
        case damaged
    }

    public static func text(for secret: RecoverySecret, createdAt: Date) -> String {
        let made = ISO8601DateFormatter().string(from: createdAt)
        // COPY BEGIN eb7806ac [NEEDS HUMAN REVIEW]
        return """
            \(header) v\(version)

            This is a skeleton key. Treat it carefully! There is no way to change it and no way to
            revoke it (besides permanently deleting it).

            It was shown once, when you set up, and none of your devices keep a copy. Using it on a
            device brings your identity back there and removes every other device, so whoever holds
            it can take your identity over.

            This will restore your identity, and you can request history backfill from the people you were talking to.

            Created: \(made)
            Fingerprint: \(fingerprint(of: secret.identity))

            KEY: \(written(secret))
            """
        // COPY END eb7806ac
    }

    public static func secret(from text: String) throws -> RecoverySecret {
        let lines = text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if let headerLine = lines.first(where: { $0.uppercased().hasPrefix(header) }) {
            let stamped = headerLine.dropFirst(header.count).trimmingCharacters(in: .whitespaces)
            if stamped.lowercased().hasPrefix("v"), let found = Int(stamped.dropFirst()) {
                if found > version { throw Failure.fromANewerVersion(found) }
                if found < version { throw Failure.fromAnEarlierVersion }
            }
        }
        if lines.contains(where: { $0.hasPrefix("SIGNING:") || $0.hasPrefix("AGREEMENT:") }) {
            throw Failure.fromAnEarlierVersion
        }

        let keyLine = lines.first { $0.uppercased().hasPrefix("KEY:") }.map {
            String($0.dropFirst("KEY:".count))
        }
        guard let candidate = keyLine ?? (lines.count == 1 ? lines.first : nil) else {
            throw lines.contains(where: { $0.uppercased().hasPrefix(header) })
                ? Failure.damaged : Failure.notARecoveryKey
        }
        guard let bytes = Base32.decode(candidate) else {
            throw keyLine == nil ? Failure.notARecoveryKey : Failure.damaged
        }
        let characters = candidate.filter { !$0.isWhitespace && $0 != "-" }.count
        guard characters == writtenLength, bytes.count == RecoverySecret.byteCount + checkLength else {
            throw keyLine == nil && !lines.contains(where: { $0.uppercased().hasPrefix(header) })
                ? Failure.notARecoveryKey : Failure.damaged
        }
        let material = bytes.prefix(RecoverySecret.byteCount)
        guard bytes.suffix(checkLength) == check(of: Data(material)) else { throw Failure.damaged }
        return try RecoverySecret(material: Data(material))
    }

    public static func fingerprint(of identity: Identity) -> String {
        identity.id.shortCode
    }

    static let checkLength = 3

    static let writtenLength = ((RecoverySecret.byteCount + checkLength) * 8 + 4) / 5

    static func written(_ secret: RecoverySecret) -> String {
        let encoded = Base32.encode(secret.material + check(of: secret.material))
        return stride(from: 0, to: encoded.count, by: 4).map { start in
            let begin = encoded.index(encoded.startIndex, offsetBy: start)
            let end = encoded.index(begin, offsetBy: min(4, encoded.count - start))
            return String(encoded[begin..<end])
        }.joined(separator: "-")
    }

    private static func check(of material: Data) -> Data {
        Data(
            SHA256.hash(data: CanonicalBytes.payload(domain: Domain.recoveryCheck, fields: [material]))
                .prefix(checkLength))
    }
}

enum Base32 {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func encode(_ data: Data) -> String {
        var out = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                out.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { out.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return out
    }

    static func decode(_ text: String) -> Data? {
        var out = Data()
        var buffer = 0
        var bits = 0
        for character in text.uppercased() {
            if character == "-" || character.isWhitespace { continue }
            let normalized: Character =
                switch character {
                case "O": "0"
                case "I", "L": "1"
                default: character
                }
            guard let value = alphabet.firstIndex(of: normalized) else { return nil }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                out.append(UInt8((buffer >> (bits - 8)) & 0xFF))
                bits -= 8
            }
            buffer &= (1 << bits) - 1
        }
        return out
    }
}
