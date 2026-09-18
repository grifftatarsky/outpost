import CryptoKit
import Foundation

/// How many characters two people read to each other.
///
/// `standard` is ten. `strict` is twenty, and is what somebody chooses when they want the check to
/// hold against an attacker with a great deal of compute rather than merely a great deal of patience.
///
/// The two are not alternatives: a phrase is taken from one deterministic stream, so **the first ten
/// characters of a strict phrase are exactly the standard phrase**. That is what makes two people who
/// have chosen differently able to talk to each other — the stricter requirement wins, and there is
/// nothing to reconcile, because the shorter phrase is a prefix of the longer one.
public enum PhraseLength: Int, Hashable, Sendable, Codable, CaseIterable, Comparable {
    case standard = 10
    case strict = 20

    public static func < (lhs: PhraseLength, rhs: PhraseLength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// What two people use when one of them asks for more than the other.
    public static func agreed(_ one: PhraseLength, _ other: PhraseLength) -> PhraseLength {
        Swift.max(one, other)
    }

    var canonicalBytes: Data { CanonicalBytes.sequence(UInt64(rawValue)) }
}

public enum ShortAuthenticationString {
    public static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Bytes at or above this are discarded. 240 is the largest multiple of thirty that fits in a
    /// byte, so every symbol is reachable from exactly eight of the 256 values. Taking `byte % 30`
    /// over the whole range instead made sixteen symbols 12.5% likelier than the other fourteen.
    static let ceiling = 256 - (256 % alphabet.count)

    public static func derive(fromTranscript transcript: Data, length: PhraseLength = .standard)
        -> String
    {
        derive(fromTranscript: transcript, length: length, domain: Domain.verificationPhrase)
    }

    static func derive(fromTranscript transcript: Data, length: PhraseLength, domain: String)
        -> String
    {
        var phrase = ""
        var block = UInt64(0)

        while phrase.count < length.rawValue {
            let digest = SHA256.hash(
                data: CanonicalBytes.payload(
                    domain: domain,
                    fields: [transcript, CanonicalBytes.sequence(block)]))

            for byte in digest where Int(byte) < ceiling {
                phrase.append(alphabet[Int(byte) % alphabet.count])
                if phrase.count == length.rawValue { break }
            }

            block += 1
        }

        return phrase
    }
}

/// What the joiner commits to before the inviter signs anything.
///
/// The attack this closes: the party who signs **last** can grind. They see the other side's keys,
/// then choose the room, the timestamps, their own keypair and — because RFC 8032 does not require a
/// deterministic nonce — the signature itself, testing candidates offline until the phrase matches
/// one they already learned from the other side of a man-in-the-middle.
///
/// So the joiner picks a random nonce, publishes only `SHA256` of it in their code, and reveals the
/// nonce **after** the inviter has signed. The phrase depends on that nonce, so the inviter has
/// nothing left to grind with, and the joiner cannot change the nonce because the commitment is in
/// the bytes the inviter signed. Each side is reduced to one blind guess.
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
                    domain: Domain.comparisonCode, fields: [keys.signing, keys.agreement])))
        for _ in 0..<iterations {
            digest = Data(SHA256.hash(data: digest + keys.signing + keys.agreement))
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
