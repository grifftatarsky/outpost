import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@MainActor
@Suite("A key a removal still owes is found in the log, not only in the state file", .serialized)
struct OwedKeyTurnTests {
    private func settle(_ sessions: [AppSession], _ mailbox: InMemoryMailbox, rounds: Int = 4) async throws {
        for _ in 0..<rounds {
            for session in sessions { _ = try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func three() async throws -> (
        alice: AppSession, bob: AppSession, carol: AppSession, room: ConversationID, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for session in [alice, bob, carol] { await session.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")
        let room = try await alice.createRoom(named: "Hangar 7")
        for joiner in [bob, carol] {
            let invite = try await alice.invite(joinerCode: joiner.identityCode(), joining: room, mailbox: nil)
            try await joiner.redeem(inviteCode: try invite.encoded())
        }
        try await settle([alice, bob, carol], mailbox, rounds: 6)
        return (alice, bob, carol, room, mailbox)
    }

    private func newest(_ session: AppSession, _ room: ConversationID) -> EpochNumber? {
        session.chains[room]?.highestKnownEpoch
    }

    @Test("A removal whose key never turned is turned on the next round, with no note of it kept")
    func aForgottenTurnIsFound() async throws {
        let (alice, bob, carol, room, mailbox) = try await three()
        let bobID = try #require(bob.enrolment?.identity.id)
        let before = try #require(newest(alice, room))

        try await alice.append(try Payload.removal(of: bobID), to: room)
        #expect(alice.persisted.epochTurnsOwed.isEmpty, "precondition: the state file remembers the turn")
        #expect(newest(alice, room) == before, "precondition: the key turned already")

        try await settle([alice, bob, carol], mailbox)
        let after = try #require(newest(alice, room))
        #expect(after > before, "a removal that no key turn followed was left standing")

        try await alice.send("after Bob", to: room)
        try await settle([alice, bob, carol], mailbox)
        let aliceID = try #require(alice.enrolment?.identity.id)
        let said = try #require(
            carol.replica.allEntries.filter { $0.author == aliceID && $0.conversation == room }
                .max { $0.seq < $1.seq })
        #expect(said.payload.epoch == after, "precondition: Alice's last words were not under the new key")
        #expect(carol.entryOpener()(said) != nil, "Carol, still in the room, cannot read it")
        #expect(bob.entryOpener()(said) == nil, "Bob reads what was said after he was removed")
    }

    @Test("A removal the key already turned for is not turned for again")
    func anAnsweredRemovalTurnsOnce() async throws {
        let (alice, bob, carol, room, mailbox) = try await three()
        let bobID = try #require(bob.enrolment?.identity.id)
        let before = try #require(newest(alice, room))

        try await alice.remove(bobID, from: room)
        let turned = try #require(newest(alice, room))
        #expect(turned == before.next)

        try await settle([alice, bob, carol], mailbox)
        #expect(newest(alice, room) == turned, "the key turned again for a removal already answered")
        #expect(alice.keyTurnsTheLogOwes().isEmpty)
    }

    @Test("Somebody removed does not turn a key in the room they were removed from")
    func theRemovedDoNotTurn() async throws {
        let (alice, bob, carol, room, mailbox) = try await three()
        let aliceID = try #require(alice.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)
        let carolDevice = try #require(carol.enrolment?.device.id)

        let turnsByAlice = {
            alice.projection.entries(of: .epochChange, by: aliceID).filter { $0.conversation == room }.count
        }
        let turnedBefore = turnsByAlice()

        try await alice.append(try Payload.removal(of: bobID), to: room)
        try await carol.remove(aliceID, from: room)
        try await settle([carol, alice], mailbox, rounds: 1)

        #expect(alice.standing(in: room) != .present, "precondition: Alice does not know she was removed")
        #expect(!alice.keyTurnsTheLogOwes().contains(room))
        #expect(turnsByAlice() == turnedBefore, "Alice turned a key in a room she had been removed from")
        #expect(
            carol.projection.entries(of: .epochChange, by: try #require(carol.enrolment?.identity.id))
                .contains { $0.conversation == room && $0.device == carolDevice },
            "precondition: Carol never turned the key when she removed Alice")
    }

    @Test("Taking the Outpost from somebody who had it, with the key never turned, is turned")
    func aForgottenOutpostTurnIsFound() async throws {
        let (alice, bob, _, _, mailbox) = try await three()
        let aliceID = try #require(alice.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        let wall = alice.outpostRoom(for: aliceID)
        let before = try #require(newest(alice, wall))

        try await alice.append(
            try Payload.outpostAccess(OutpostAccessBody(person: bobID, isAllowed: false, chosenIn: nil)),
            to: wall)
        #expect(newest(alice, wall) == before, "precondition: the key turned already")

        try await settle([alice, bob], mailbox)
        #expect(
            try #require(newest(alice, wall)) > before,
            "taking the Outpost from Bob left him holding the key that opens it")
    }

    @Test("Saying no to somebody who never had the Outpost turns nothing")
    func aRefusalTurnsNothing() async throws {
        let (alice, bob, carol, _, mailbox) = try await three()
        let aliceID = try #require(alice.enrolment?.identity.id)
        let carolID = try #require(carol.enrolment?.identity.id)
        try await alice.allowOutpost(try #require(bob.enrolment?.identity.id), everything: true)
        let wall = alice.outpostRoom(for: aliceID)
        let before = try #require(newest(alice, wall))

        try await alice.revokeOutpost(carolID)
        try await settle([alice, bob, carol], mailbox)
        #expect(newest(alice, wall) == before, "a refusal turned the Outpost's key for every reader")
    }
}
