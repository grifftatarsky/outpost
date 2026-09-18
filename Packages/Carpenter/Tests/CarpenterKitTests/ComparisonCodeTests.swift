@testable import CarpenterKit
import Foundation
import Testing

@Suite("The code two people compare later is the same on both phones, and costs a full search to fake")
struct ComparisonCodeTests {
    @Test("Both phones show the same two halves, in the same order")
    func symmetric() {
        let alice = Identity.generate()
        let carol = Identity.generate()
        let onAlices = ComparisonCode.between(alice.publicKeys, carol.publicKeys)
        let onCarols = ComparisonCode.between(carol.publicKeys, alice.publicKeys)
        #expect(onAlices.map(\.1) == onCarols.map(\.1))
        #expect(onAlices.map(\.0) == onCarols.map(\.0))
    }

    @Test("A half is ten characters from the reading alphabet")
    func shape() {
        let half = ComparisonCode.half(for: Identity.generate().publicKeys)
        #expect(half.count == PhraseLength.standard.rawValue)
        #expect(half.allSatisfy { ShortAuthenticationString.alphabet.contains($0) })
    }

    @Test("Somebody substituted into the middle shows a different half")
    func substitutionShows() {
        let carol = Identity.generate()
        let impostor = Identity.generate()
        #expect(ComparisonCode.half(for: carol.publicKeys) != ComparisonCode.half(for: impostor.publicKeys))
    }

    @Test("A half depends on each key, not only on the pair of them")
    func eachKeyCounts() {
        let one = Identity.generate().publicKeys
        let other = Identity.generate().publicKeys
        let swapped = IdentityPublicKeys(signing: one.signing, agreement: other.agreement)
        #expect(ComparisonCode.half(for: one) != ComparisonCode.half(for: swapped))
    }

    @Test("The derivation is pinned, so a later build cannot silently show different codes")
    func pinned() {
        let keys = IdentityPublicKeys(
            signing: Data(repeating: 0x11, count: 32), agreement: Data(repeating: 0x22, count: 32))
        #expect(ComparisonCode.iterations == 4096)
        #expect(ComparisonCode.half(for: keys) == "RRPM3B8CGJ", "computed independently, in Python, from the layout in the crypto brief")
    }
}
