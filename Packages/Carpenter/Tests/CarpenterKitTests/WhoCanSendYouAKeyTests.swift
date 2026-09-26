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
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
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
            to: try #require(giver.pairwiseSecret(with: takerID)))
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
        try await alice.adopt(grant, from: from)

        #expect(
            alice.chains[room]?.highestKnownEpoch == highest,
            """
            Somebody removed from the room sent a newer key and it was accepted. The newest key \
            is the one this member writes under and passes on to everybody else in the room, so the \
            removed member would read what the room says next.
            """)
    }

    @Test("A key sent by somebody still in the room is accepted")
    func aMembersKeyIsTaken() async throws {
        let (alice, bob, _, room) = try await joined()
        let highest = try #require(alice.chains[room]?.highestKnownEpoch)

        let (grant, from) = try newKey(sentBy: bob, to: alice, in: room, at: highest.next)
        try await alice.adopt(grant, from: from)

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
        try await alice.adopt(grant, from: from)

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
        try await alice.adopt(grant, from: from)

        #expect(alice.chains[wall] == nil, "a key to Carol's Outpost was accepted from Bob")
    }

    @Test("A key sent for an epoch already held does not replace it")
    func aHeldKeyIsKept() async throws {
        let (alice, bob, _, room) = try await joined()
        let highest = try #require(alice.chains[room]?.highestKnownEpoch)
        let held = try #require(try alice.chains[room]?.secret(for: highest))

        let (grant, from) = try newKey(sentBy: bob, to: alice, in: room, at: highest)
        try await alice.adopt(grant, from: from)

        #expect(
            try alice.chains[room]?.secret(for: highest) == held,
            "a second key for the same epoch replaced the one everybody else is using")
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
