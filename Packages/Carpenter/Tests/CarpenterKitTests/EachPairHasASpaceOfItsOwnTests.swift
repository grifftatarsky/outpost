@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Each pair of people has a space of its own in each one's iCloud", .serialized)
struct EachPairHasASpaceOfItsOwnTests {
    @MainActor
    private struct Three {
        let mailbox: InMemoryMailbox
        let alice: AppSession
        let bob: AppSession
        let carol: AppSession
        let room: RoomID

        var aliceID: ParticipantID { alice.enrolment!.identity.id }
        var bobID: ParticipantID { bob.enrolment!.identity.id }
        var carolID: ParticipantID { carol.enrolment!.identity.id }

        func settle(_ sessions: [AppSession]? = nil, rounds: Int = 5) async throws {
            for _ in 0..<rounds {
                for session in sessions ?? [alice, bob, carol] { try await session.sync(through: mailbox, media: mailbox) }
            }
        }
    }

    private func three() async throws -> Three {
        let mailbox = InMemoryMailbox()
        let (alice, bob, carol) = (TestSession.make(), TestSession.make(), TestSession.make())
        for (session, name) in [(alice, "Alice"), (bob, "Bob"), (carol, "Carol")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        let room = try await alice.createRoom(named: "Lanterns")
        try await join(bob, into: room, of: alice, through: mailbox)
        try await join(carol, into: room, of: alice, through: mailbox)
        let three = Three(mailbox: mailbox, alice: alice, bob: bob, carol: carol, room: room)
        try await three.settle()
        try #require(alice.roster(of: room).members.count == 3, "precondition: three members")
        return three
    }

    @Test("Every space is read by the one person it is for, and by nobody else")
    func everySpaceHasOneReader() async throws {
        let t = try await three()
        for owner in [t.aliceID, t.bobID, t.carolID] {
            for readers in await t.mailbox.readers(ofSpaceOf: owner) {
                #expect(readers.count <= 1, "a space was read by \(readers.count) people")
            }
        }
        let accounts = Set([t.bobID, t.carolID].map(LocalPairStore.account(of:)))
        let aliceReaders = await t.mailbox.readers(ofSpaceOf: t.aliceID).reduce(Set<String>()) { $0.union($1) }
        #expect(aliceReaders == accounts, "Alice's spaces were read by somebody other than the two she talks to")
    }

    @Test("Two people who never swapped codes get spaces of their own through the room, and talk without its host")
    func aRoomIntroducesItsMembers() async throws {
        let t = try await three()
        #expect(t.bob.pairsJoined.contains(t.carolID), "Bob never joined a space of Carol's")
        #expect(t.carol.pairsJoined.contains(t.bobID), "Carol never joined a space of Bob's")

        try await t.bob.send("just between the room, without Alice around", to: t.room)
        try await t.settle([t.bob, t.carol], rounds: 3)
        #expect(
            t.carol.messages(in: t.room).contains { $0.body == "just between the room, without Alice around" },
            "a message from Bob reached Carol only through Alice")
    }

    @Test("The member who passes a link along cannot open it")
    func theRelayCannotReadTheLink() async throws {
        let t = try await three()
        let projected = t.alice.projection
        var passed: [PairLinkBody] = []
        for link in projected.pairLinks(in: t.room, to: t.carolID) where link.entry.author == t.bobID {
            passed.append(link.body)
        }
        let body = try #require(passed.last, "precondition: Alice holds the link Bob sent Carol")
        let alicesView = try #require(t.alice.legacySecret(with: t.bobID))
        #expect(body.open(from: t.bobID, with: alicesView) == nil, "the member in the middle read a link meant for Carol")
        let carolsView = try #require(t.carol.legacySecret(with: t.bobID))
        #expect(body.open(from: t.bobID, with: carolsView) != nil, "the person a link was for could not read it")
    }

    @Test("A link a removed member sends after the removal is not taken")
    func aRemovedMembersLinkIsIgnored() async throws {
        let t = try await three()
        let before = t.carol.persisted.pairBook[t.bobID]?.theirs
        try await t.alice.remove(t.bobID, from: t.room)
        try await t.settle(rounds: 3)

        let bob = try #require(t.bob.enrolment)
        let feed = FeedKey(author: t.bobID, device: bob.device.id)
        let head = t.bob.replica.highestSequence(in: feed).flatMap { t.bob.replica.entries(in: feed, at: $0).first }
        let chain = try #require(t.bob.chains[t.room])
        let forged = PairLink(account: "_the-thief", url: URL(string: "https://icloud.invalid/share/thief")!)
        let entry = try Entry.append(
            to: head, author: t.bobID, device: bob.device, clock: t.bob.replica.frontier,
            wallTime: TestSession.now, room: t.room,
            payload: try Payload.pairLink(
                try PairLinkBody.seal(forged, from: t.bobID, to: t.carolID, with: try #require(t.bob.legacySecret(with: t.carolID)))),
            at: try #require(chain.highestKnownEpoch), sealedWith: chain)
        try t.bob.replica.integrate(entry)
        t.bob.sendOwnEntries()
        try await t.settle([t.bob, t.carol], rounds: 3)

        #expect(
            t.carol.persisted.pairBook[t.bobID]?.theirs == before,
            "a link sent after its sender was removed replaced the one Carol had")
    }

    @Test("A link swapped in a code on its way is refused, and the inviter keeps no link for the joiner")
    func aSwappedLinkIsRefused() async throws {
        let mailbox = InMemoryMailbox()
        let (alice, bob) = (TestSession.make(), TestSession.make())
        for (session, name) in [(alice, "Alice"), (bob, "Bob")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        let room = try await alice.createRoom(named: "Lanterns")
        let honest = try JoinerCode.decoded(from: await bob.joinerCode(through: mailbox))
        let signed = try #require(honest.pair)
        let swapped = JoinerCode(
            keys: honest.keys, commitment: honest.commitment, requires: honest.requires,
            pair: SignedPairLink(
                link: PairLink(account: "_the-thief", url: URL(string: "https://icloud.invalid/share/thief")!),
                signature: signed.signature))

        let invite = try await alice.invite(joinerCode: try swapped.encoded(), joining: room, through: mailbox)
        #expect(invite.pair == nil, "an invite answered a code whose link did not verify")
        #expect(
            alice.persisted.pairBook[honest.participantID]?.theirs == nil,
            "the inviter took a link somebody changed on its way")
    }

    @Test("Closing a person's space ends their access to it and touches nobody else's")
    func closingEndsOnePersonsAccess() async throws {
        let t = try await three()
        await t.alice.close(pairWith: t.bobID, through: t.mailbox)
        try await t.alice.send("after the door closed", to: t.room)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)

        let tags = SyncSession.recentTags(
            for: try #require(t.bob.peers().first { $0.them == t.aliceID }), at: TestSession.now)
        #expect(
            try await t.mailbox.fetch(from: t.aliceID, for: tags, in: try t.bob.currentPairs()).isEmpty,
            "Bob still read Alice's space after she closed it")
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        #expect(
            t.carol.messages(in: t.room).contains { $0.body == "after the door closed" },
            "closing Bob's space cut off Carol")
    }

    @Test("Blocking somebody closes the space kept for them, and unblocking them opens a new one")
    func blockingClosesTheirSpace() async throws {
        let t = try await three()
        let bobs = LocalPairStore.account(of: t.bobID)
        #expect(await t.mailbox.readers(ofSpaceOf: t.aliceID).contains { $0.contains(bobs) }, "precondition: Bob reads Alice")

        await t.alice.block(t.bobID)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        #expect(
            !(await t.mailbox.readers(ofSpaceOf: t.aliceID).contains { $0.contains(bobs) }),
            "somebody blocked could still read the space kept for them")

        await t.alice.unblock(t.bobID)
        try await t.settle(rounds: 4)
        try await t.alice.send("back again", to: t.room)
        try await t.settle(rounds: 3)
        #expect(t.bob.messages(in: t.room).contains { $0.body == "back again" }, "unblocking never let them read again")

        await t.alice.block(t.bobID)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        #expect(
            !(await t.mailbox.readers(ofSpaceOf: t.aliceID).contains { $0.contains(bobs) }),
            "blocking somebody a second time left their space open")
    }

    @Test("Nothing a contact does from their side changes or removes what is in your space")
    func aContactCannotTouchYourSpace() async throws {
        let t = try await three()
        let before = Set(await t.mailbox.writtenPackets)
        try await t.alice.send("left alone", to: t.room)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        let written = await t.mailbox.writtenPackets.filter { !before.contains($0) }
        let sent = await t.mailbox.everySentPacket
        let forBob = try #require(written.first { sent[$0]?.to == t.bobID })
        let digest = sent[forBob]?.contentDigest

        let bobs = try t.bob.currentPairs()
        try await t.mailbox.withdraw(forBob, in: bobs)
        try await t.mailbox.acknowledge(
            forBob, from: t.aliceID, with: SealedReceipt(tag: RecipientTag(rawValue: Data([1])), sealed: Data([2])), in: bobs)

        #expect(await t.mailbox.everySentPacket[forBob]?.contentDigest == digest, "Bob changed or removed Alice's packet")
    }

    @Test("A message rings the space of each person it is for, and only theirs")
    func ringsGoToTheReaders() async throws {
        let t = try await three()
        let before = await t.mailbox.rings.count
        try await t.alice.send("ring the two of you", to: t.room)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        let rung = await t.mailbox.rings.dropFirst(before)
        #expect(Set(rung.map(\.to)) == [t.bobID, t.carolID])
        #expect(rung.allSatisfy { $0.from == t.aliceID }, "somebody rang from a space that was not their own")
    }
}
