import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

private actor RefusingMailbox: Mailbox {
    private let inner = InMemoryMailbox()
    private var refusal: MailboxFailure?

    func refuse(_ failure: MailboxFailure) { refusal = failure }

    func relent() { refusal = nil }

    func put(_ packet: SyncPacket) async throws {
        if let refusal { throw refusal }
        try await inner.put(packet)
    }

    func fetch(for tags: Set<RecipientTag>) async throws -> [SyncPacket] {
        try await inner.fetch(for: tags)
    }

    func acknowledge(_ id: PacketID, by tags: Set<RecipientTag>) async throws {
        try await inner.acknowledge(id, by: tags)
    }

    func pendingDeliveries() async throws -> [PacketID: Set<RecipientTag>] {
        try await inner.pendingDeliveries()
    }

    func ring(_ bell: MessageBell) async throws {
        try await inner.ring(bell)
    }
}

@MainActor
@Suite("An account with no room to send", .serialized)
struct NoRoomToSendTests {
    private func pair() async throws -> (
        mine: AppSession, room: ConversationID, mailbox: RefusingMailbox
    ) {
        let mailbox = RefusingMailbox()
        let clock = TestClock(now: TestSession.now)
        let mine = TestSession.make(clock: clock)
        let theirs = TestSession.make(clock: clock)
        for session in [mine, theirs] { await session.load() }
        try await mine.createIdentity(displayName: "Griff")
        try await theirs.createIdentity(displayName: "Outie")

        let room = try await mine.createRoom(named: "Kitchen")
        let invite = try await mine.invite(
            joinerCode: theirs.identityCode(), joining: room, mailbox: nil)
        try await theirs.redeem(inviteCode: try invite.encoded())
        try await mine.sync(through: mailbox)
        try await theirs.accept(
            invite.attestation, from: try #require(mine.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [mine, theirs] { try await session.sync(through: mailbox) }
        }
        return (mine, room, mailbox)
    }

    @Test("A full iCloud is named, not swallowed")
    func aFullICloudIsNamed() async throws {
        let (session, room, mailbox) = try await pair()
        await mailbox.refuse(.noRoomInICloud)
        try await session.send("does this go", to: room)
        _ = try? await session.sync(through: mailbox)

        #expect(
            session.cannotSend == .noRoomInICloud,
            """
            A round that could write nothing left no trace on the session. This is the silent \
            failure Griff named on 2026-09-12: the packet does not go and nothing on screen says why.
            """)
    }

    @Test("Being signed out says so, and says something different")
    func beingSignedOutSaysSo() async throws {
        let (session, room, mailbox) = try await pair()
        await mailbox.refuse(.notSignedIn)
        try await session.send("does this go", to: room)
        _ = try? await session.sync(through: mailbox)

        #expect(session.cannotSend == .notSignedIn)
        #expect(
            SessionProblem.sentence(for: MailboxFailure.notSignedIn)
                != SessionProblem.sentence(for: MailboxFailure.noRoomInICloud),
            "two different causes were given the same sentence, so neither names its fix")
    }

    @Test("The next round that writes clears it")
    func theNextRoundThatWritesClearsIt() async throws {
        let (session, room, mailbox) = try await pair()
        await mailbox.refuse(.noRoomInICloud)
        try await session.send("does this go", to: room)
        _ = try? await session.sync(through: mailbox)
        #expect(session.cannotSend != nil)

        await mailbox.relent()
        _ = try? await session.sync(through: mailbox)

        #expect(
            session.cannotSend == nil,
            "the warning outlived the problem, which teaches people to ignore it")
    }

    @Test("Nothing is lost: the entries go on the round that works")
    func nothingIsLost() async throws {
        let (session, room, mailbox) = try await pair()
        await mailbox.refuse(.noRoomInICloud)
        try await session.send("does this go", to: room)
        _ = try? await session.sync(through: mailbox)

        await mailbox.relent()
        let report = try await session.sync(through: mailbox)

        #expect(
            report.entriesSent > 0,
            "a refused round marked its entries sent, so they were never offered again")
    }

    @Test("The sentence names the fix and does not blame the app")
    func theSentenceNamesTheFix() {
        for refusal in [MailboxFailure.noRoomInICloud, .notSignedIn] {
            let sentence = SessionProblem.sentence(for: refusal)
            #expect(!sentence.isEmpty)
            #expect(
                !sentence.lowercased().contains("error")
                    && !sentence.lowercased().contains("failed"),
                """
                "\(sentence)" reads as the app being broken. It is working exactly as designed — \
                Griff, 2026-09-12 — and the copy has to say what to do instead.
                """)
            #expect(
                sentence.contains("Settings") || sentence.contains("Sign in"),
                "\"\(sentence)\" does not name the way out")
        }
    }
}
