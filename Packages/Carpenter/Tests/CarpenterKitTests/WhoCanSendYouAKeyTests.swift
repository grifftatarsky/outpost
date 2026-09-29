import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp
@testable import CarpenterKit

@Suite("Who can send you a room key", .serialized)
@MainActor
struct WhoCanSendYouAKeyTests {
    private func joined() async throws -> (alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox, room: RoomID) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: await bob.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, mailbox, room)
    }

    private func newKey(
        sentBy giver: AppSession, to taker: AppSession, in room: RoomID, at epoch: EpochNumber
    ) throws -> (grant: EpochGrant, from: Peer) {
        let giverID = try #require(giver.enrolment?.identity.id)
        let takerID = try #require(taker.enrolment?.identity.id)
        let grant = try EpochGrant.issue(
            EpochSecret.random(), at: epoch, in: room, link: nil,
            to: try #require(giver.pairwiseSecret(with: takerID)),
            devices: giver.deviceRecipients(of: takerID)
        ).signed(by: try #require(giver.enrolment?.device), from: giverID, to: takerID)
        return (grant, Peer(secret: try #require(taker.pairwiseSecret(with: giverID)), them: giverID, me: takerID))
    }

    @Test("A key sent by somebody removed from the room is refused")
    func aRemovedMembersKeyIsRefused() async throws {
        let (alice, bob, _, room) = try await joined()
        let bobID = try #require(bob.enrolment?.identity.id)
        #expect(alice.roster(of: room).members.contains(bobID), "precondition: Bob is in")
        try await alice.remove(bobID, from: room)
        let highest = try #require(alice.chains[room]?.highestKnownEpoch)

        let (grant, from) = try newKey(sentBy: bob, to: alice, in: room, at: highest.next)
        try await alice.adopt(grant, from: from, storedAt: .distantFuture)

        #expect(
            alice.chains[room]?.highestKnownEpoch == highest,
            """
            Somebody removed from the room sent a newer key and it was accepted. The newest key \
            is the one this member writes under and passes on to everybody else in the room, so the \
            removed member would read what the room says next.
            """)
    }

    private func befriended(with host: AppSession, through mailbox: InMemoryMailbox) async throws -> AppSession {
        let friend = TestSession.make()
        await friend.load()
        try await friend.createIdentity(displayName: "Friend")
        let kitchen = try await host.createRoom(named: "Kitchen")
        let invite = try await host.invite(
            joinerCode: await friend.joinerCode(through: mailbox), joining: kitchen, through: mailbox)
        try await friend.redeem(inviteCode: try invite.encoded())
        try await host.sync(through: mailbox)
        try await friend.accept(invite.attestation, from: try #require(host.enrolment?.identity.publicKeys))
        for _ in 0..<2 {
            try await host.sync(through: mailbox)
            try await friend.sync(through: mailbox)
        }
        return friend
    }

    @Test("A key sent by somebody who was never in the room is refused")
    func anOutsidersKeyIsRefused() async throws {
        let (alice, _, mailbox, room) = try await joined()
        let carol = try await befriended(with: alice, through: mailbox)
        let aliceID = try #require(alice.enrolment?.identity.id)
        let carolID = try #require(carol.enrolment?.identity.id)
        try #require(!carol.deviceRecipients(of: aliceID).isEmpty, "precondition: Carol can seal a key to Alice's phone")
        #expect(!alice.roster(of: room).members.contains(carolID), "precondition: Carol was never in this room")
        let highest = try #require(alice.chains[room]?.highestKnownEpoch)

        let (grant, from) = try newKey(sentBy: carol, to: alice, in: room, at: highest.next)
        try await alice.adopt(grant, from: from, storedAt: .distantFuture)

        #expect(
            alice.chains[room]?.highestKnownEpoch == highest,
            """
            Somebody who was never in the room sent a newer key for it and it was taken. This member writes \
            under the newest key it holds and passes it on to everybody in the room, so the sender would \
            read what the room says next.
            """)
    }

    @Test("A joining device takes its first key for a room only from the person who invited it")
    func aJoinerTakesItsFirstKeyFromItsInviter() async throws {
        let (alice, bob, mailbox, room) = try await joined()
        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.remove(bobID, from: room)
        let eve = try await befriended(with: bob, through: mailbox)
        let invite = try await alice.invite(
            joinerCode: await eve.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await eve.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await eve.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        let eveID = try #require(eve.enrolment?.identity.id)
        try #require(!bob.deviceRecipients(of: eveID).isEmpty, "precondition: Bob can seal a key to Eve's phone")
        try #require(eve.chains[room] == nil, "precondition: the joining phone holds no key for the room yet")

        let (grant, from) = try newKey(sentBy: bob, to: eve, in: room, at: .initial)
        try await eve.adopt(grant, from: from, storedAt: .distantFuture)

        #expect(
            eve.chains[room] == nil,
            """
            Somebody removed from the room sent a key to a phone that was joining it, and the phone took it. \
            A joining phone cannot read who is in the room yet, so it writes under the first key it holds; \
            the one who made it up would read what the newcomer says.
            """)
    }

    @Test("A first key for a room this phone holds nothing of, from somebody who did not invite it, is refused")
    func aFirstKeyNeedsAVoucher() async throws {
        let (alice, _, mailbox, room) = try await joined()
        let carol = try await befriended(with: alice, through: mailbox)
        let carolID = try #require(carol.enrolment?.identity.id)
        try #require(!alice.deviceRecipients(of: carolID).isEmpty, "precondition: Alice can seal a key to Carol's phone")
        try #require(carol.chains[room] == nil, "precondition: Carol holds no key for this room")

        let (grant, from) = try newKey(sentBy: alice, to: carol, in: room, at: .initial)
        try await carol.adopt(grant, from: from, storedAt: .distantFuture)

        #expect(carol.chains[room] == nil, "a phone took a room's key from somebody who never let it in")
    }

    @Test("A key sent by somebody still in the room is accepted")
    func aMembersKeyIsTaken() async throws {
        let (alice, bob, _, room) = try await joined()
        let highest = try #require(alice.chains[room]?.highestKnownEpoch)

        let (grant, from) = try newKey(sentBy: bob, to: alice, in: room, at: highest.next)
        try await alice.adopt(grant, from: from, storedAt: .distantFuture)

        #expect(alice.chains[room]?.highestKnownEpoch == highest.next)
    }

    @Test("Nobody else can send you a key to your own Outpost")
    func yourOwnOutpostKeyIsYours() async throws {
        let (alice, bob, _, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        let wall = alice.outpostRoom(for: aliceID)
        try await alice.send("the first thing on my Outpost", to: nil)
        let highest = try #require(alice.chains[wall]?.highestKnownEpoch)

        let (grant, from) = try newKey(sentBy: bob, to: alice, in: wall, at: highest.next)
        try await alice.adopt(grant, from: from, storedAt: .distantFuture)

        #expect(
            alice.chains[wall]?.highestKnownEpoch == highest,
            """
            Somebody else sent this member a newer key for their own Outpost and it was accepted. \
            Their next post would be sealed under it, readable by whoever made it and passed on to \
            every reader.
            """)
    }

    @Test("Only its owner can send you a key to somebody's Outpost")
    func anOutpostKeyComesFromItsOwner() async throws {
        let (alice, bob, _, _) = try await joined()
        let carolKeys = Identity.generate().publicKeys
        alice.replica.introduce(carolKeys)
        let wall = alice.outpostRoom(for: carolKeys.participantID)

        let (grant, from) = try newKey(sentBy: bob, to: alice, in: wall, at: .initial)
        try await alice.adopt(grant, from: from, storedAt: .distantFuture)

        #expect(alice.chains[wall] == nil, "a key to Carol's Outpost was accepted from Bob")
    }

    @Test("A key sent for an epoch already held does not replace it")
    func aHeldKeyIsKept() async throws {
        let (alice, bob, _, room) = try await joined()
        let highest = try #require(alice.chains[room]?.highestKnownEpoch)
        let held = try #require(try alice.chains[room]?.secret(for: highest))

        let (grant, from) = try newKey(sentBy: bob, to: alice, in: room, at: highest)
        try await alice.adopt(grant, from: from, storedAt: .distantFuture)

        #expect(
            try alice.chains[room]?.secret(for: highest) == held,
            "a second key for the same epoch replaced the one everybody else is using")
        #expect(
            alice.writingKey(of: room)?.secret == held,
            "a key slipped in beside the one everybody is using, with no record of who made it, was written under")
    }
}

@Suite("The links between a room's keys")
struct EpochLinkTests {
    @Test("A link that does not open under the key it names is refused, and the one that does is kept")
    func aBrokenLinkIsRefused() throws {
        let room = RoomID()
        var (chain, first) = EpochChain.create(room: room)
        let (second, link) = try EpochChain.advance(from: first, at: .initial, room: room)
        chain.adopt(second, at: .initial.next)
        try chain.record(link)

        try chain.record(EpochLink(room: room, epoch: .initial.next, wrapped: Data(repeating: 1, count: 60)))

        #expect(chain.link(at: .initial.next) == link)
        var fresh = EpochChain(room: room)
        fresh.adopt(second, at: .initial.next)
        try fresh.record(EpochLink(room: room, epoch: .initial.next, wrapped: Data(repeating: 1, count: 60)))
        try fresh.record(link)
        #expect(try fresh.secret(for: .initial) == first)
    }

    @Test("There is no epoch after the last one")
    func theLastEpochDoesNotAdvance() {
        let room = RoomID()
        #expect(throws: CryptoError.self) {
            try EpochChain.advance(from: EpochSecret.random(), at: EpochNumber(rawValue: .max), room: room)
        }
    }
}
