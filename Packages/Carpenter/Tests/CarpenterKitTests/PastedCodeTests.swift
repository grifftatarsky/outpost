import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Pasting a code somebody sent you")
struct PastedCodeTests {
    private let scheme = "outpost"

    private func identity() -> Identity { Identity.generate() }
    private func keys() -> IdentityPublicKeys { identity().publicKeys }

    private func code(_ keys: IdentityPublicKeys? = nil) -> JoinerCode {
        let mine = keys ?? self.keys()
        return JoinerCode(
            keys: mine, commitment: JoinCommitment.of(TestInvite.nonce(for: mine)))
    }

    @Test("A code shared as a link can be pasted straight back in")
    func sharedCodeLinkPastes() throws {
        let original = code()
        let shared = try InviteLink.url(offering: original, scheme: scheme).absoluteString

        #expect(shared.hasPrefix("outpost://code?c="), "the share format changed; so must this test")
        #expect(try JoinerCode.decoded(from: shared) == original)
    }

    @Test("A bare payload still pastes")
    func barePayloadStillPastes() throws {
        let original = code()
        #expect(try JoinerCode.decoded(from: original.encoded()) == original)
    }

    @Test("A link that arrived wrapped across lines still pastes")
    func wrappedLinkPastes() throws {
        let original = code()
        let shared = try InviteLink.url(offering: original, scheme: scheme).absoluteString
        let wrapped = stride(from: 0, to: shared.count, by: 40).map { start -> String in
            let from = shared.index(shared.startIndex, offsetBy: start)
            let to = shared.index(from, offsetBy: min(40, shared.count - start))
            return String(shared[from..<to])
        }.joined(separator: "\n")

        #expect(try JoinerCode.decoded(from: wrapped) == original)
    }

    @Test("Nonsense is still refused")
    func nonsenseIsRefused() {
        #expect(throws: (any Error).self) { try IdentityPublicKeys.decoded(from: "hello") }
        #expect(throws: (any Error).self) {
            try IdentityPublicKeys.decoded(from: "outpost://code?c=not-a-real-payload")
        }
        #expect(throws: (any Error).self) { try IdentityPublicKeys.decoded(from: "") }
    }

    @Test("An invite shared as a link can be pasted straight back in")
    func sharedInviteLinkPastes() throws {
        let inviter = identity()
        let joiner = keys()
        let attestation = try TestInvite.issue(
            joining: RoomID(), joinerKeys: joiner, by: inviter, at: Date(timeIntervalSince1970: 0))
        let invite = Invite(attestation: attestation, mailbox: nil)

        let shared = try InviteLink.url(inviting: invite, scheme: scheme).absoluteString
        let read = try Invite.decoded(from: shared)

        #expect(read.attestation == attestation)
    }

    @Test("Reading a system link still checks the scheme")
    func systemLinkReadingStaysStrict() throws {
        let original = code()
        let shared = try InviteLink.url(offering: original, scheme: scheme)
        let foreign = URL(string: shared.absoluteString.replacingOccurrences(
            of: "outpost://", with: "somethingelse://"))!

        #expect(InviteLink.read(shared, scheme: scheme) != nil)
        #expect(InviteLink.read(foreign, scheme: scheme) == nil)
    }
}
