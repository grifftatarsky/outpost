import CryptoKit
import Foundation
import Testing

@testable import CarpenterKit

@Suite("The verification phrase")
struct VerificationPhraseTests {

    private func transcript(_ n: Int) -> Data { Data("transcript-\(n)".utf8) }

    // MARK: How long it is

    @Test("Ten characters by default, from the agreed alphabet")
    func shape() {
        let phrase = ShortAuthenticationString.derive(fromTranscript: transcript(1))
        #expect(phrase.count == 10)
        #expect(phrase.allSatisfy(ShortAuthenticationString.alphabet.contains))
    }

    @Test("Twenty when somebody asks for twenty")
    func strict() {
        let phrase = ShortAuthenticationString.derive(fromTranscript: transcript(1), length: .strict)
        #expect(phrase.count == 20)
        #expect(phrase.allSatisfy(ShortAuthenticationString.alphabet.contains))
    }

    @Test("A long phrase begins with the short one, character for character")
    func longerIsAPrefixExtension() {
        for n in 0..<200 {
            let short = ShortAuthenticationString.derive(fromTranscript: transcript(n))
            let long = ShortAuthenticationString.derive(
                fromTranscript: transcript(n), length: .strict)
            #expect(long.hasPrefix(short))
        }
    }

    @Test("The stricter of the two is what they read")
    func strictestWins() {
        #expect(PhraseLength.agreed(.standard, .strict) == .strict)
        #expect(PhraseLength.agreed(.strict, .standard) == .strict)
        #expect(PhraseLength.agreed(.strict, .strict) == .strict)
        #expect(PhraseLength.agreed(.standard, .standard) == .standard)
    }

    // MARK: How it is derived

    @Test("The same transcript always gives the same phrase")
    func deterministic() {
        #expect(
            ShortAuthenticationString.derive(fromTranscript: transcript(7))
                == ShortAuthenticationString.derive(fromTranscript: transcript(7)))
    }

    @Test("A different transcript gives a different phrase")
    func distinct() {
        #expect(
            ShortAuthenticationString.derive(fromTranscript: transcript(1))
                != ShortAuthenticationString.derive(fromTranscript: transcript(2)))
    }

    @Test("Every symbol is drawn from the same number of byte values")
    func noModuloBias() {
        #expect(ShortAuthenticationString.ceiling == 240)
        #expect(ShortAuthenticationString.ceiling % ShortAuthenticationString.alphabet.count == 0)

        var reachable: [Character: Int] = [:]
        for byte in 0..<ShortAuthenticationString.ceiling {
            reachable[
                ShortAuthenticationString.alphabet[byte % ShortAuthenticationString.alphabet.count],
                default: 0] += 1
        }

        #expect(reachable.count == ShortAuthenticationString.alphabet.count)
        #expect(Set(reachable.values) == [ShortAuthenticationString.ceiling / 30])
    }

    @Test("The distribution of first characters is flat across many transcripts")
    func flatInPractice() {
        var seen: [Character: Int] = [:]
        let runs = 30_000
        for n in 0..<runs { seen[ShortAuthenticationString.derive(fromTranscript: transcript(n)).first!, default: 0] += 1 }

        #expect(seen.count == ShortAuthenticationString.alphabet.count)
        let expected = Double(runs) / Double(ShortAuthenticationString.alphabet.count)
        for (symbol, count) in seen {
            #expect(
                abs(Double(count) - expected) / expected < 0.15,
                "\(symbol) appeared \(count) times against an expected \(Int(expected))")
        }
    }

    @Test("It keeps going until it has enough, however many bytes it rejects")
    func survivesRejection() {
        for n in 0..<3_000 {
            #expect(ShortAuthenticationString.derive(fromTranscript: transcript(n)).count == 10)
            #expect(
                ShortAuthenticationString.derive(fromTranscript: transcript(n), length: .strict)
                    .count == 20)
        }
    }

    // MARK: The commitment

    @Test("A nonce opens its own commitment and nothing else")
    func commitmentOpens() {
        let nonce = JoinCommitment.nonce()
        #expect(nonce.count == JoinCommitment.nonceBytes)
        #expect(JoinCommitment.opens(nonce, JoinCommitment.of(nonce)))
        #expect(!JoinCommitment.opens(JoinCommitment.nonce(), JoinCommitment.of(nonce)))
        #expect(!JoinCommitment.opens(Data(), JoinCommitment.of(nonce)))
    }

    @Test("Two nonces are not the same nonce")
    func noncesAreFresh() {
        #expect(Set((0..<500).map { _ in JoinCommitment.nonce() }).count == 500)
    }

    @Test("The commitment is a hash, so it gives the nonce away to nobody")
    func commitmentHidesTheNonce() {
        let nonce = JoinCommitment.nonce()
        let commitment = JoinCommitment.of(nonce)
        #expect(commitment != nonce)
        #expect(commitment.count == SHA256.byteCount)
        #expect(!commitment.starts(with: nonce.prefix(4)))
    }
}
