import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("Controls that are drawn do something", .serialized)
struct NoDeadControlsTests {
    @Test("A code that has not parsed is not a code")
    func aCodeThatHasNotParsedIsNotACode() async throws {
        let session = TestSession.make()
        await session.load()
        try await session.createIdentity(displayName: "Griff")

        #expect(
            InviteLink.namesSomebody(session.identityCode()),
            "this member's own code was not recognised as one")
        #expect(
            InviteLink.namesSomebody("  \(session.identityCode())\n"),
            "a code with whitespace around it, which is how a paste arrives, was refused")

        for notACode in [
            "", "   ", "1600 Pennsylvania Avenue NW, Washington, DC 20500",
            "https://example.com", "outpost://invite?c=nonsense",
        ] {
            #expect(
                !InviteLink.namesSomebody(notACode),
                """
                "\(notACode)" lit the Create the invite button. The button is claiming a code has \
                been read when nothing has parsed it — noticed 2026-09-09 when the simulator's \
                pasteboard handed the sheet a postal address.
                """)
        }
    }

    @Test("A removed member cannot be offered a control that would be refused")
    func aRemovedMemberIsNotOfferedTheRemoveControl() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let host = TestSession.make(clock: clock)
        let other = TestSession.make(clock: clock)
        for session in [host, other] { await session.load() }
        try await host.createIdentity(displayName: "Griff")
        try await other.createIdentity(displayName: "Outie")

        let room = try await host.createRoom(named: "Kitchen")
        let invite = try await host.invite(
            joinerCode: other.identityCode(), joining: room, mailbox: nil)
        try await other.redeem(inviteCode: try invite.encoded())
        try await host.sync(through: mailbox)
        try await other.accept(
            invite.attestation, from: try #require(host.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [host, other] { try await session.sync(through: mailbox) }
        }

        #expect(other.standing(in: room).mayWrite, "the fixture never joined")

        try await host.remove(try #require(other.enrolment?.identity.id), from: room)
        for _ in 0..<6 {
            for session in [host, other] { try await session.sync(through: mailbox) }
        }

        #expect(
            !other.standing(in: room).mayWrite,
            """
            Somebody put out of a room still reads as able to write in it, so the members sheet \
            goes on offering them Remove from room — a control whose attempt is refused underneath. \
            That is the shape this codebase keeps removing.
            """)
    }
}
