import CryptoKit
import Foundation

public enum PhraseLength: Int, Hashable, Sendable, Codable, CaseIterable, Comparable {
    case standard = 10
    case strict = 20

    public static func < (lhs: PhraseLength, rhs: PhraseLength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func agreed(_ one: PhraseLength, _ other: PhraseLength) -> PhraseLength {
        Swift.max(one, other)
    }

    var canonicalBytes: Data { CanonicalBytes.sequence(UInt64(rawValue)) }
}

public enum ShortAuthenticationString {
    public static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let digits = Array("0123456789")

    static let ceiling = 256 - (256 % alphabet.count)

    public static func derive(fromTranscript transcript: Data, length: PhraseLength = .standard)
        -> String
    {
        derive(fromTranscript: transcript, length: length, domain: Domain.verificationPhrase)
    }

    static func derive(fromTranscript transcript: Data, length: PhraseLength, domain: String)
        -> String
    {
        derive(fromTranscript: transcript, count: length.rawValue, domain: domain, from: alphabet)
    }

    static func derive(fromTranscript transcript: Data, count: Int, domain: String, from symbols: [Character])
        -> String
    {
        let ceiling = 256 - (256 % symbols.count)
        var phrase = ""
        var block = UInt64(0)

        while phrase.count < count {
            let digest = SHA256.hash(
                data: CanonicalBytes.payload(
                    domain: domain,
                    fields: [transcript, CanonicalBytes.sequence(block)]))

            for byte in digest where Int(byte) < ceiling {
                phrase.append(symbols[Int(byte) % symbols.count])
                if phrase.count == count { break }
            }

            block += 1
        }

        return phrase
    }
}

public enum JoinCommitment {
    public static let nonceBytes = 32

    public static func nonce() -> Data {
        Data(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }

    public static func of(_ nonce: Data) -> Data {
        Data(
            SHA256.hash(
                data: CanonicalBytes.payload(domain: Domain.joinCommitment, fields: [nonce])))
    }

    public static func opens(_ nonce: Data, _ commitment: Data) -> Bool {
        of(nonce) == commitment
    }
}

public enum ComparisonCode {
    public static let iterations = 4096

    public static func half(for keys: IdentityPublicKeys) -> String {
        var digest = Data(
            SHA256.hash(
                data: CanonicalBytes.payload(
                    domain: Domain.comparisonCode, fields: [keys.signing, keys.agreement, keys.recovery])))
        for _ in 0..<iterations {
            digest = Data(SHA256.hash(data: digest + keys.signing + keys.agreement + keys.recovery))
        }
        return ShortAuthenticationString.derive(
            fromTranscript: digest, length: .standard, domain: Domain.comparisonCode)
    }

    public static func between(_ one: IdentityPublicKeys, _ other: IdentityPublicKeys)
        -> [(ParticipantID, String)]
    {
        [(one.participantID, half(for: one)), (other.participantID, half(for: other))]
            .sorted { $0.0.rawValue.lexicographicallyPrecedes($1.0.rawValue) }
    }
}
