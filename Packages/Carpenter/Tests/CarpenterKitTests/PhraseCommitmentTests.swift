@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import CryptoKit
import Foundation
import Testing

/// The commitment, end to end through two sessions.
///
/// The attack it closes: the party who signs **last** can grind. They see the other side's keys,
/// then choose the room, the timestamps, their own keypair and — because RFC 8032 does not require a
/// deterministic nonce — the signature itself, testing candidates offline until the phrase matches
/// one they already learned from the other side of a man-in-the-middle. Ten characters prices that
/// attack out of the time an invitation is open; the commitment removes it.
@MainActor
@Suite("The verification phrase is committed before it is signed")
struct PhraseCommitmentTests {

    private func pair() async throws -> (alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        return (alice, bob, mailbox)
    }

    // MARK: What the inviter can and cannot see

    @Test("The inviter cannot compute the phrase from the invitation alone")
    func inviterIsBlindUntilTheJoinerOpens() async throws {
        let (alice, bob, _) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)

        #expect(
            alice.phrase(for: invite.attestation) == nil,
            """
            The inviter could read the phrase straight off an invitation they had just signed. That \
            is the whole attack: everything they contributed was chosen after they saw the joiner's \
            keys, so a phrase they can compute is a phrase they can grind.
            """)

        #expect(
            invite.attestation.verificationPhrase(opening: nil) == nil,
            "a nil nonce opened the commitment")
        #expect(
            invite.attestation.verificationPhrase(opening: JoinCommitment.nonce()) == nil,
            "somebody else's nonce opened the commitment")
    }

    @Test("The joiner has it as soon as they redeem")
    func theJoinerHasItImmediately() async throws {
        let (alice, bob, _) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())

        let theirs = try #require(bob.phrase(for: invite.attestation))
        #expect(theirs.count == PhraseLength.standard.rawValue)
    }

    @Test("It reaches the inviter once the joiner has confirmed, and both agree")
    func bothSidesAgreeAfterAConfirmation() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: room, of: alice, through: mailbox)

        let mine = try #require(bob.ownInvitation(to: room)?.attestation)
        let bobID = try #require(bob.enrolment?.identity.id)
        let theirs = try #require(alice.roster(of: room).requests[bobID])

        let his = try #require(bob.phrase(for: mine))
        let hers = try #require(alice.phrase(for: theirs))
        #expect(his == hers, "the two sides derived different phrases for the same join")
        #expect(his.count == PhraseLength.standard.rawValue)
    }

    // MARK: The commitment actually binds

    @Test("A confirmation carrying the wrong nonce is refused")
    func aSubstitutedNonceIsRefused() async throws {
        let (alice, bob, _) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)

        let identity = try #require(bob.enrolment?.identity)
        let honest = try JoinConfirmedBody.signed(
            confirming: invite.attestation,
            opening: try #require(bob.nonce(opening: invite.attestation.joinerCommitment)),
            by: identity)
        #expect(throws: Never.self) { try honest.verify(confirming: invite.attestation) }

        // Signed properly by the real joiner, but opening with a nonce they never committed to.
        let swapped = try JoinConfirmedBody.signed(
            confirming: invite.attestation, opening: JoinCommitment.nonce(), by: identity)
        #expect(throws: MembershipError.commitmentNotOpened) {
            try swapped.verify(confirming: invite.attestation)
        }
    }

    @Test("The nonce is inside what the joiner signs, so it cannot be swapped in transit")
    func theNonceIsSigned() async throws {
        let (alice, bob, _) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)

        let identity = try #require(bob.enrolment?.identity)
        let honest = try JoinConfirmedBody.signed(
            confirming: invite.attestation,
            opening: try #require(bob.nonce(opening: invite.attestation.joinerCommitment)),
            by: identity)

        let tampered = JoinConfirmedBody(
            invitation: honest.invitation, joiner: honest.joiner,
            nonce: JoinCommitment.nonce(), signature: honest.signature)
        #expect(throws: MembershipError.self) { try tampered.verify(confirming: invite.attestation) }
    }

    @Test("Each code carries its own commitment, so one is never two")
    func codesAreSingleUse() async throws {
        let (_, bob, _) = try await pair()
        let commitments = try (0..<20).map { _ in
            try JoinerCode.decoded(from: bob.identityCode()).commitment
        }
        #expect(Set(commitments).count == 20, "a code was handed out twice with the same commitment")
        for commitment in commitments {
            #expect(bob.nonce(opening: commitment) != nil, "the device forgot a nonce it minted")
        }
    }

    // MARK: Twenty characters

    @Test("Twenty when the joiner asks for twenty, and the first ten are unchanged")
    func theJoinerCanAskForTwenty() async throws {
        let (alice, bob, _) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")

        await bob.setRequiresLongPhrase(true)
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())

        #expect(invite.attestation.phraseLength == .strict)
        let long = try #require(bob.phrase(for: invite.attestation))
        #expect(long.count == 20)

        let nonce = try #require(bob.nonce(opening: invite.attestation.joinerCommitment))
        let short = ShortAuthenticationString.derive(
            fromTranscript: invite.attestation.signingPayload + nonce, length: .standard)
        #expect(long.hasPrefix(short), "the long phrase is not an extension of the short one")
    }

    @Test("Twenty when the inviter asks for twenty, even though the joiner did not")
    func theInviterCanAskForTwenty() async throws {
        let (alice, bob, _) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")

        await alice.setRequiresLongPhrase(true)
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())

        #expect(invite.attestation.joinerRequires == .standard)
        #expect(invite.attestation.inviterRequires == .strict)
        #expect(invite.attestation.phraseLength == .strict)
        #expect(bob.phrase(for: invite.attestation)?.count == 20)
    }

    @Test("Ten when neither asks for more")
    func tenByDefault() async throws {
        let (alice, bob, _) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")

        #expect(!alice.requiresLongPhrase)
        #expect(!bob.requiresLongPhrase)

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        #expect(bob.phrase(for: invite.attestation)?.count == 10)
    }

    @Test("Both sides of a mixed pair read the same twenty characters")
    func theStricterSideWinsOverTheWire() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")

        await bob.setRequiresLongPhrase(true)
        try await join(bob, into: room, of: alice, through: mailbox)

        let mine = try #require(bob.ownInvitation(to: room)?.attestation)
        let bobID = try #require(bob.enrolment?.identity.id)
        let theirs = try #require(alice.roster(of: room).requests[bobID])

        let his = try #require(bob.phrase(for: mine))
        let hers = try #require(alice.phrase(for: theirs))
        #expect(his == hers)
        #expect(
            his.count == 20,
            "Alice never asked for twenty, but Bob did, and the stricter of the two is what they read")
    }

    @Test("The setting survives a relaunch")
    func theSettingPersists() async throws {
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "phrase-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = TestSession.make(keychain: keychain, at: directory)
        await session.load()
        try await session.createIdentity(displayName: "Alice")
        await session.setRequiresLongPhrase(true)

        let relaunched = TestSession.make(keychain: keychain, at: directory)
        await relaunched.load()
        #expect(relaunched.requiresLongPhrase)
    }
}

@MainActor
@Suite("Showing your code does not mint a new one")
struct CodeForSharingTests {

    @Test("Reading the code to show it is free, however often a screen draws")
    func readingDoesNotMint() async throws {
        let session = TestSession.make()
        await session.load()
        try await session.createIdentity(displayName: "Alice")

        let shown = session.codeForSharing
        #expect(!shown.isEmpty, "there is no code to share once the account is ready")

        let nonces = session.persisted.phraseNonces.count
        for _ in 0..<200 { _ = session.codeForSharing }

        #expect(session.codeForSharing == shown, "reading the code changed it")
        #expect(
            session.persisted.phraseNonces.count == nonces,
            "reading the code 200 times minted \(session.persisted.phraseNonces.count - nonces) nonces")
    }

    @Test("A refresh does not mint a second code while one is standing")
    func refreshKeepsTheStandingCode() async throws {
        let session = TestSession.make()
        await session.load()
        try await session.createIdentity(displayName: "Alice")

        let shown = session.codeForSharing
        for _ in 0..<20 { session.refresh() }
        #expect(session.codeForSharing == shown)
    }

    @Test("Once the code is used, the next one is different")
    func aSpentCodeIsReplaced() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Hangar 7")

        let before = bob.codeForSharing
        let invite = try await alice.invite(joinerCode: before, joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        _ = mailbox

        #expect(
            bob.codeForSharing != before,
            "a code whose commitment has been used is still being offered, so the next person to get it could be ground against")
        #expect(!bob.codeForSharing.isEmpty)
    }
}
