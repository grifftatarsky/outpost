@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Checking who you are talking to, through the app", .serialized)
struct SoloVerificationTests {
    private func solo() async throws -> (
        alice: AppSession, bob: AppSession, room: ConversationID, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let bobID = try #require(bob.enrolment?.identity.id)
        let room = try await alice.startSolo(with: bobID)
        try await join(bob, into: room, of: alice, through: mailbox)
        return (alice, bob, room, mailbox)
    }

    private func settle(
        _ everyone: [AppSession], _ mailbox: InMemoryMailbox, rounds: Int = 5
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox) }
        }
    }

    @Test("A solo nobody has asked about says nothing")
    func nothingAsked() async throws {
        let (alice, _, room, _) = try await solo()
        #expect(alice.soloCheck(in: room).state == .notChecked)
        #expect(alice.canWrite(in: room))
    }

    @Test("Both sides already have the same six characters")
    func bothSidesHaveThePhrase() async throws {
        let (alice, bob, room, _) = try await solo()
        let bobID = try #require(bob.enrolment?.identity.id)

        let theirs = try #require(alice.roster(of: room).requests[bobID])
        let mine = try #require(bob.ownInvitation(to: room)?.attestation)
        let hers = try #require(alice.phrase(for: theirs))
        let his = try #require(bob.phrase(for: mine))
        #expect(hers == his)
        #expect(!hers.isEmpty)
    }

    @Test("Asking is outstanding on both devices, and says who asked")
    func askingReachesBoth() async throws {
        let (alice, bob, room, mailbox) = try await solo()
        let aliceID = try #require(alice.enrolment?.identity.id)

        try await alice.askWhoYouAreTalkingTo(in: room, holding: false)
        try await settle([alice, bob], mailbox)

        guard case .outstanding(let askedBy, _) = alice.soloCheck(in: room).state else {
            Issue.record("the asker's own device did not show it outstanding")
            return
        }
        #expect(askedBy == aliceID)
        guard case .outstanding(let seenBy, _) = bob.soloCheck(in: room).state else {
            Issue.record("the other device never heard about it")
            return
        }
        #expect(seenBy == aliceID)
    }

    @Test("Holding closes the asker's composer and nobody else's")
    func theHoldIsTheAskersOwn() async throws {
        let (alice, bob, room, mailbox) = try await solo()

        try await alice.askWhoYouAreTalkingTo(in: room, holding: true)
        try await settle([alice, bob], mailbox)

        #expect(!alice.canWrite(in: room), "the asker chose to hold and was not held")
        #expect(
            bob.canWrite(in: room),
            "asking froze the other person's conversation, which anybody could then do to anybody")
    }

    @Test("The other side is told a check was asked for")
    func theOtherSideIsTold() async throws {
        let (alice, bob, room, mailbox) = try await solo()
        try await alice.askWhoYouAreTalkingTo(in: room, holding: true)
        try await settle([alice, bob], mailbox)

        let notices = bob.transcript(in: room).compactMap { entry -> RoomNotice.Kind? in
            if case .notice(let notice) = entry { return notice.kind }
            return nil
        }
        #expect(notices.contains { if case .checkAsked = $0 { return true } else { return false } })
    }

    @Test("Asking without holding leaves the asker talking")
    func askingWithoutHolding() async throws {
        let (alice, bob, room, mailbox) = try await solo()
        try await alice.askWhoYouAreTalkingTo(in: room, holding: false)
        try await settle([alice, bob], mailbox)

        #expect(alice.canWrite(in: room))
        #expect(bob.canWrite(in: room))
        #expect(alice.soloCheck(in: room).isOutstanding)
    }

    @Test("Answering settles it, and lifts the asker's hold")
    func answeringLiftsTheHold() async throws {
        let (alice, bob, room, mailbox) = try await solo()
        try await alice.askWhoYouAreTalkingTo(in: room, holding: true)
        try await settle([alice, bob], mailbox)
        #expect(!alice.canWrite(in: room), "precondition: she is holding")

        try await bob.answerWhoYouAreTalkingTo(in: room, matched: true)
        try await settle([alice, bob], mailbox)

        guard case .confirmed = alice.soloCheck(in: room).state else {
            Issue.record("the answer never settled it: \(alice.soloCheck(in: room).state)")
            return
        }
        #expect(alice.canWrite(in: room), "the hold outlived the question it was waiting on")
        #expect(bob.canWrite(in: room))
    }

    @Test("A refusal blocks the conversation on both devices")
    func aRefusalBlocksBoth() async throws {
        let (alice, bob, room, mailbox) = try await solo()
        try await alice.askWhoYouAreTalkingTo(in: room, holding: false)
        try await settle([alice, bob], mailbox)

        try await bob.answerWhoYouAreTalkingTo(in: room, matched: false)
        try await settle([alice, bob], mailbox)

        #expect(alice.soloCheck(in: room).isBlocked)
        #expect(bob.soloCheck(in: room).isBlocked)
        #expect(!alice.canWrite(in: room))
        #expect(!bob.canWrite(in: room))
    }

    @Test("A refusal takes nothing away")
    func aRefusalDeletesNothing() async throws {
        let (alice, bob, room, mailbox) = try await solo()
        try await alice.send("before we checked", to: room)
        try await settle([alice, bob], mailbox)

        try await alice.askWhoYouAreTalkingTo(in: room, holding: false)
        try await settle([alice, bob], mailbox)
        try await bob.answerWhoYouAreTalkingTo(in: room, matched: false)
        try await settle([alice, bob], mailbox)

        #expect(bob.messages(in: room).map(\.body).contains("before we checked"))
        #expect(alice.messages(in: room).map(\.body).contains("before we checked"))
    }

    @Test("Checking again and confirming reopens it")
    func checkingAgainReopensIt() async throws {
        let (alice, bob, room, mailbox) = try await solo()
        try await alice.askWhoYouAreTalkingTo(in: room, holding: false)
        try await settle([alice, bob], mailbox)
        try await bob.answerWhoYouAreTalkingTo(in: room, matched: false)
        try await settle([alice, bob], mailbox)
        #expect(!alice.canWrite(in: room), "precondition: blocked")

        try await alice.askWhoYouAreTalkingTo(in: room, holding: false)
        try await settle([alice, bob], mailbox)
        try await bob.answerWhoYouAreTalkingTo(in: room, matched: true)
        try await settle([alice, bob], mailbox)

        #expect(alice.canWrite(in: room))
        #expect(bob.canWrite(in: room))
    }

    @Test("A held conversation refuses the write, not just the button")
    func theSessionRefusesTheWrite() async throws {
        let (alice, bob, room, mailbox) = try await solo()
        try await alice.askWhoYouAreTalkingTo(in: room, holding: true)
        try await settle([alice, bob], mailbox)

        await #expect(throws: MembershipError.soloNotVerified) {
            try await alice.send("while I am holding", to: room)
        }
        try await bob.send("carrying on", to: room)
    }

    @Test("A blocked conversation refuses the write on both sides")
    func aBlockedConversationRefusesWrites() async throws {
        let (alice, bob, room, mailbox) = try await solo()
        try await alice.askWhoYouAreTalkingTo(in: room, holding: false)
        try await settle([alice, bob], mailbox)
        try await bob.answerWhoYouAreTalkingTo(in: room, matched: false)
        try await settle([alice, bob], mailbox)

        await #expect(throws: MembershipError.soloNotVerified) {
            try await alice.send("after the refusal", to: room)
        }
        await #expect(throws: MembershipError.soloNotVerified) {
            try await bob.send("after the refusal", to: room)
        }
    }

    @Test("Checking again is always allowed, however shut the conversation is")
    func theCheckItselfIsAlwaysAllowed() async throws {
        let (alice, bob, room, mailbox) = try await solo()
        try await alice.askWhoYouAreTalkingTo(in: room, holding: true)
        try await settle([alice, bob], mailbox)
        try await bob.answerWhoYouAreTalkingTo(in: room, matched: false)
        try await settle([alice, bob], mailbox)
        #expect(alice.soloCheck(in: room).isBlocked, "precondition: blocked")

        try await alice.askWhoYouAreTalkingTo(in: room, holding: false)
        try await settle([alice, bob], mailbox)
        try await bob.answerWhoYouAreTalkingTo(in: room, matched: true)
        try await settle([alice, bob], mailbox)

        try await alice.send("we sorted it out", to: room)
        #expect(alice.messages(in: room).map(\.body).contains("we sorted it out"))
    }

    @Test("Requiring a check does not stop a solo being started")
    func theSettingDoesNotStopStartingOne() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await alice.setRequiresSoloCheck(true)

        let bobID = try #require(bob.enrolment?.identity.id)
        let room = try await alice.startSolo(with: bobID)
        try await join(bob, into: room, of: alice, through: mailbox)

        #expect(alice.roster(of: room).members.count == 2, "the setting stopped the join")
        try await alice.leave(room)
    }

    @Test("Somebody who did not ask can still answer")
    func theOtherSideCanAnswer() async throws {
        let (alice, bob, room, mailbox) = try await solo()
        try await alice.askWhoYouAreTalkingTo(in: room, holding: false)
        try await settle([alice, bob], mailbox)

        #expect(bob.canWrite(in: room))
        try await bob.answerWhoYouAreTalkingTo(in: room, matched: true)
        try await settle([alice, bob], mailbox)

        #expect(alice.soloCheck(in: room).isConfirmed)
        #expect(bob.soloCheck(in: room).isConfirmed)
    }

    @Test("It is not offered in a room")
    func notInARoom() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: room, of: alice, through: mailbox)

        #expect(!alice.canCheckWhoTheyAreTalkingTo(in: room))
        await #expect(throws: AppSessionError.cannotWriteThere) {
            try await alice.askWhoYouAreTalkingTo(in: room, holding: false)
        }
    }
}

@MainActor
@Suite("Requiring a check before a solo opens", .serialized)
struct RequiringSoloCheckTests {
    @Test("It is off by default, and never answered is not the same as answered no")
    func offByDefault() async throws {
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")

        #expect(!alice.requiresSoloCheck)
        #expect(alice.hasAnsweredSoloCheckQuestion == false, "an unasked question read as answered")

        await alice.setRequiresSoloCheck(false)
        #expect(!alice.requiresSoloCheck)
        #expect(alice.hasAnsweredSoloCheckQuestion, "answering no did not count as answering")
    }

    @Test("With it on, an unchecked solo is held and the other side is told why")
    func anUncheckedSoloIsHeld() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        await bob.setRequiresSoloCheck(true)

        let bobID = try #require(bob.enrolment?.identity.id)
        let room = try await alice.startSolo(with: bobID)
        try await join(bob, into: room, of: alice, through: mailbox)
        for _ in 0..<5 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(!bob.canWrite(in: room), "the setting held nothing")
        #expect(bob.soloCheck(in: room).isOutstanding, "being held did not raise the check")
        #expect(alice.soloCheck(in: room).isOutstanding, "the sender was never told it was held")
        #expect(alice.canWrite(in: room), "one person's setting closed the other person's composer")
    }
}
