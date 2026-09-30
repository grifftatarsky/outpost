@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Claiming the space a code offered")
struct ClaimingTheSpaceACodeOfferedTests {
    private struct Two {
        let mailbox = InMemoryMailbox()
        let alice = Identity.generate()
        let bob = Identity.generate()
        let toAlice: Peer
        let toBob: Peer

        init() throws {
            (toBob, toAlice) = try peers(alice, bob)
        }

        var asAlice: Pairs { Pairs.of(toBob) }
        var asBob: Pairs { Pairs.of(toAlice) }
    }

    @Test("The space the other side holds is kept when nobody reads the one already made")
    func theCodesSpaceIsKept() async throws {
        let t = try Two()
        let code = try await t.mailbox.spaceForACode(in: t.asBob)
        _ = try await t.mailbox.space(for: t.alice.id, naming: nil, in: t.asBob)
        let bobsAccount = try await t.mailbox.account(in: t.asBob)
        let alicesAccount = try await t.mailbox.account(in: t.asAlice)

        let claimed = try await t.mailbox.claim(code, for: t.alice.id, naming: alicesAccount, in: t.asBob)

        #expect(claimed == code, "the claim threw away the only space Alice was ever told about")
        let joined = try await t.mailbox.join(PairLink(account: bobsAccount, url: code), of: t.bob.id, in: t.asAlice)
        #expect(joined == .joined, "Alice could not read the space Bob's code offered her")
        #expect(try await t.mailbox.reads(t.bob.id, in: t.asAlice))
    }

    @Test("A space the other side already reads is kept, and the code's is let go")
    func aSpaceAlreadyReadIsKept() async throws {
        let t = try Two()
        _ = try await link(t.toAlice, t.toBob, through: t.mailbox)
        try #require(try await t.mailbox.reads(t.bob.id, in: t.asAlice), "precondition: Alice already reads Bob's space")
        let code = try await t.mailbox.spaceForACode(in: t.asBob)
        let alicesAccount = try await t.mailbox.account(in: t.asAlice)

        let claimed = try await t.mailbox.claim(code, for: t.alice.id, naming: alicesAccount, in: t.asBob)

        #expect(claimed != code, "Bob started a second space for somebody who already reads one")
        #expect(try await t.mailbox.reads(t.bob.id, in: t.asAlice), "the claim cut off a pair that was working")
    }
}
