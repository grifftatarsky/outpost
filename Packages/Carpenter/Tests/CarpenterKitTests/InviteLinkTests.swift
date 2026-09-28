import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Invite links")
struct InviteLinkTests {
    private let scheme = "outposttest"

    private func keys() throws -> IdentityPublicKeys {
        Identity.generate().publicKeys
    }

    private func invite() throws -> Invite {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        return Invite(
            attestation: try TestInvite.issue(
                joining: RoomID(), joinerKeys: joiner.publicKeys, by: inviter,
                at: TestSession.now),
            pair: try SignedPairLink.sign(
                PairLink(account: "_inviter", url: URL(string: "https://www.icloud.com/share/example")!), by: inviter))
    }

    @Test("A code survives the round trip")
    func codeRoundTrips() throws {
        let keys = try keys()
        let mine = JoinerCode(
            keys: keys, commitment: JoinCommitment.of(TestInvite.nonce(for: keys)))
        let url = try InviteLink.url(offering: mine, scheme: scheme)

        guard case .code(let read) = InviteLink.read(url, scheme: scheme) else {
            Issue.record("the link did not read back as a code")
            return
        }
        #expect(read == mine)
    }

    @Test("An invite survives the round trip, its signed link and all")
    func inviteRoundTrips() throws {
        let issued = try invite()
        let url = try InviteLink.url(inviting: issued, scheme: scheme)

        guard case .invite(let read) = InviteLink.read(url, scheme: scheme) else {
            Issue.record("the link did not read back as an invite")
            return
        }
        #expect(read == issued)
        #expect(read.verifiedPair == issued.verifiedPair, "the inviter's link is what lets the joiner read them")
        #expect(read.verifiedPair != nil, "the link's signature did not survive the envelope")
        #expect(
            read.attestation.testPhrase == issued.attestation.testPhrase,
            "the phrase is the whole security check and has to survive the envelope")
    }

    @Test("Both spellings of the same link open")
    func opaqueFormIsAccepted() throws {
        let issued = try invite()
        let payload = try issued.encoded()
        let opaque = URL(string: "\(scheme):invite?c=\(payload)")!

        guard case .invite(let read) = InviteLink.read(opaque, scheme: scheme) else {
            Issue.record("the opaque spelling did not read back")
            return
        }
        #expect(read == issued)
    }

    @Test("Somebody else's link is not ours")
    func foreignSchemeIsRefused() throws {
        let url = try InviteLink.url(inviting: try invite(), scheme: scheme)
        #expect(InviteLink.read(url, scheme: "somethingelse") == nil)
    }

    @Test("A link of ours carrying rubbish is refused rather than guessed at")
    func malformedPayloadIsRefused() {
        let url = URL(string: "\(scheme)://invite?c=not-an-invite")!
        #expect(InviteLink.read(url, scheme: scheme) == nil)
    }

    @Test("A link with no payload is refused")
    func missingPayloadIsRefused() {
        #expect(InviteLink.read(URL(string: "\(scheme)://invite")!, scheme: scheme) == nil)
    }

    @Test("An invite that arrived as a link joins a room")
    @MainActor
    func aLinkJoinsARoom() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()

        let alice = AppSession(storage: TestSession.storage(), clock: clock)
        let bob = AppSession(storage: TestSession.storage(), clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let bobsLink = try InviteLink.url(
            offering: try JoinerCode.decoded(from: await bob.joinerCode(through: mailbox)), scheme: scheme)
        guard case .code(let bobsKeys) = InviteLink.read(bobsLink, scheme: scheme) else {
            Issue.record("Bob's code did not survive the link")
            return
        }

        let room = try await alice.createRoom(named: "Hangar 7")
        let issued = try await alice.invite(
            joinerCode: try bobsKeys.encoded(), joining: room, through: mailbox)

        let inviteLink = try InviteLink.url(inviting: issued, scheme: scheme)
        guard case .invite(let arriving) = InviteLink.read(inviteLink, scheme: scheme) else {
            Issue.record("the invite did not survive the link")
            return
        }
        try await bob.redeem(inviteCode: try arriving.encoded())

        for _ in 0..<3 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        #expect(bob.rooms.contains { $0.id == room }, "the joiner never got into the room")
    }
}
