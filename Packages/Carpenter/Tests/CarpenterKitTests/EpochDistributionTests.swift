import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Epoch distribution")
struct EpochDistributionTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func pair() throws -> (Identity, Identity, PairwiseSecret) {
        let a = Identity.generate()
        let b = Identity.generate()
        let secret = try PairwiseSecret.derive(mine: a, theirs: b.publicKeys)
        return (a, b, secret)
    }

    @Test("A grant opens under the pairwise secret it was issued to")
    func grantRoundTrip() throws {
        let room = RoomID()
        let (_, _, shared) = try pair()
        let (_, founding) = EpochChain.create(room: room)
        let advanced = try EpochChain.advance(from: founding, at: .initial, room: room)

        let grant = try EpochGrant.issue(
            advanced.secret, at: .initial.next, link: advanced.link, to: shared)

        #expect(try grant.open(with: shared) == advanced.secret)
        #expect(grant.room == room)
        #expect(grant.epoch == .initial.next)
    }

    @Test("A grant issued to one member does not open for another")
    func grantIsBoundToItsRecipient() throws {
        let room = RoomID()
        let (alice, _, toBob) = try pair()
        let carol = Identity.generate()
        let toCarol = try PairwiseSecret.derive(mine: alice, theirs: carol.publicKeys)

        let (_, founding) = EpochChain.create(room: room)
        let advanced = try EpochChain.advance(from: founding, at: .initial, room: room)
        let grant = try EpochGrant.issue(
            advanced.secret, at: .initial.next, link: advanced.link, to: toBob)

        #expect(throws: CryptoError.openFailed) { try grant.open(with: toCarol) }
    }

    @Test("One grant walks a joiner back through every earlier epoch")
    func oneGrantReadsAllHistory() throws {
        let room = RoomID()
        let (_, _, shared) = try pair()
        var author = EpochChain(room: room)

        let (_, founding) = EpochChain.create(room: room)
        author.adopt(founding, at: .initial)

        var secrets: [EpochNumber: EpochSecret] = [.initial: founding]
        var published: [EpochNumber: EpochLink] = [:]
        var current = founding
        var epoch = EpochNumber.initial

        for _ in 0..<4 {
            let advanced = try EpochChain.advance(from: current, at: epoch, room: room)
            epoch = epoch.next
            current = advanced.secret
            secrets[epoch] = current
            published[epoch] = advanced.link
            author.adopt(current, at: epoch)
            try author.record(advanced.link)
        }

        let grant = try EpochGrant.issue(current, at: epoch, link: published[epoch]!, to: shared)
        var joiner = EpochChain(room: room)
        try joiner.adopt(grant, using: shared)

        var cursor = epoch
        while let step = cursor.previous {
            #expect(try joiner.secret(for: step) == secrets[step])
            if let older = published[step] { try joiner.record(older) }
            cursor = step
        }

        #expect(try joiner.secret(for: .initial) == founding)
    }

    @Test("A new epoch secret is fresh, not derived from the one before it")
    func advancingIsNotDerivable() throws {
        let room = RoomID()
        let (_, founding) = EpochChain.create(room: room)

        let first = try EpochChain.advance(from: founding, at: .initial, room: room)
        let second = try EpochChain.advance(from: founding, at: .initial, room: room)

        #expect(first.secret != founding)
        #expect(first.secret != second.secret)
    }

    @Test("A removed member keeps what it had and gains nothing")
    func removalSticks() throws {
        let room = RoomID()
        let (_, founding) = EpochChain.create(room: room)

        var removed = EpochChain(room: room)
        removed.adopt(founding, at: .initial)

        let advanced = try EpochChain.advance(from: founding, at: .initial, room: room)
        try removed.record(advanced.link)

        #expect(throws: CryptoError.unknownEpoch) {
            try removed.secret(for: .initial.next)
        }
        #expect(try removed.secret(for: .initial) == founding)
    }

    @Test("A grant for one room is refused and leaves nothing behind")
    func grantIsBoundToItsRoom() throws {
        let room = RoomID()
        let (_, _, shared) = try pair()
        let (_, founding) = EpochChain.create(room: room)
        let advanced = try EpochChain.advance(from: founding, at: .initial, room: room)
        let grant = try EpochGrant.issue(
            advanced.secret, at: .initial.next, link: advanced.link, to: shared)

        var elsewhere = EpochChain(room: RoomID())
        #expect(throws: (any Error).self) { try elsewhere.adopt(grant, using: shared) }
        #expect(elsewhere.knownEpochs.isEmpty)
    }

    @Test(
        "Relabelling a grant breaks it",
        arguments: [false, true]
    )
    func grantWrapIsBoundToWhatItClaims(moveRoom: Bool) throws {
        let room = RoomID()
        let (_, _, shared) = try pair()
        let (_, founding) = EpochChain.create(room: room)
        let advanced = try EpochChain.advance(from: founding, at: .initial, room: room)
        let grant = try EpochGrant.issue(
            advanced.secret, at: .initial.next, link: advanced.link, to: shared)

        let relabelled = EpochGrant(
            room: moveRoom ? RoomID() : grant.room,
            epoch: moveRoom ? grant.epoch : grant.epoch.next,
            link: grant.link,
            wrapped: grant.wrapped
        )

        #expect(throws: CryptoError.openFailed) { try relabelled.open(with: shared) }
    }

    // MARK: Distribution through the packet

    @Test("A grant rides along with the entries and reaches only its recipient")
    func packetCarriesGrant() throws {
        let room = RoomID()
        let alice = Identity.generate()
        let bob = Identity.generate()
        let carol = Identity.generate()
        let toBob = try PairwiseSecret.derive(mine: alice, theirs: bob.publicKeys)
        let toCarol = try PairwiseSecret.derive(mine: alice, theirs: carol.publicKeys)

        let (chain, founding) = EpochChain.create(room: room)
        var author = Author(chain: chain)
        let entry = try author.append(try Payload.post("evening"), at: start, room: room)

        let advanced = try EpochChain.advance(from: founding, at: .initial, room: room)
        let grant = try EpochGrant.issue(
            advanced.secret, at: .initial.next, link: advanced.link, to: toBob)

        let bobFromAlice = Peer(secret: toBob, them: bob.id, me: alice.id)
        let carolFromAlice = Peer(secret: toCarol, them: carol.id, me: alice.id)
        let aliceFromBob = Peer(secret: toBob, them: alice.id, me: bob.id)
        let aliceFromCarol = Peer(secret: toCarol, them: alice.id, me: carol.id)

        let packet = try SyncEngine.pack(
            [entry], for: [bobFromAlice, carolFromAlice],
            granting: [(to: bobFromAlice, grant: grant)], window: 0)

        let asBob = try SyncEngine.unpack(packet, as: aliceFromBob, window: 0)
        #expect(asBob.entries.count == 1)
        #expect(try asBob.grants.first?.open(with: toBob) == advanced.secret)

        let asCarol = try SyncEngine.unpack(packet, as: aliceFromCarol, window: 0)
        #expect(asCarol.entries.count == 1)
        #expect(asCarol.grants.isEmpty)
    }

    @Test("Two keys owed to one person in the same round both arrive")
    func packetCarriesEveryGrantForOneRecipient() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let toBob = try PairwiseSecret.derive(mine: alice, theirs: bob.publicKeys)
        let bobFromAlice = Peer(secret: toBob, them: bob.id, me: alice.id)
        let aliceFromBob = Peer(secret: toBob, them: alice.id, me: bob.id)

        let first = RoomID()
        let second = RoomID()
        let (_, firstFounding) = EpochChain.create(room: first)
        let (_, secondFounding) = EpochChain.create(room: second)
        let firstAdvanced = try EpochChain.advance(from: firstFounding, at: .initial, room: first)
        let secondAdvanced = try EpochChain.advance(from: secondFounding, at: .initial, room: second)
        let toFirst = try EpochGrant.issue(
            firstAdvanced.secret, at: .initial.next, in: first, link: firstAdvanced.link, to: toBob)
        let toSecond = try EpochGrant.issue(
            secondAdvanced.secret, at: .initial.next, in: second, link: secondAdvanced.link,
            to: toBob)

        let packet = try SyncEngine.pack(
            [], for: [bobFromAlice],
            granting: [(to: bobFromAlice, grant: toFirst), (to: bobFromAlice, grant: toSecond)],
            window: 0)

        let carried = try #require(PacketWire.packet(from: PacketWire.fields(of: packet)))
        let opened = try SyncEngine.unpack(carried, as: aliceFromBob, window: 0)

        #expect(opened.grants.count == 2, "one of the two keys was dropped in the packet")
        let secrets = try opened.grants.map { try $0.open(with: toBob) }
        #expect(Set(opened.grants.map(\.room)) == [first, second])
        #expect(Set(secrets) == Set([firstAdvanced.secret, secondAdvanced.secret]))
    }

    @Test("A packet with no grants still carries entries")
    func packetWithoutGrants() throws {
        let room = RoomID()
        let alice = Identity.generate()
        let bob = Identity.generate()
        let toBob = try PairwiseSecret.derive(mine: alice, theirs: bob.publicKeys)

        let (chain, _) = EpochChain.create(room: room)
        var author = Author(chain: chain)
        let entry = try author.append(try Payload.post("still here"), at: start, room: room)

        let packet = try SyncEngine.pack(
            [entry], for: [Peer(secret: toBob, them: bob.id, me: alice.id)], window: 0)
        let opened = try SyncEngine.unpack(
            packet, as: Peer(secret: toBob, them: alice.id, me: bob.id), window: 0)

        #expect(opened.entries.count == 1)
        #expect(opened.grants.isEmpty)
    }

    // MARK: The published link

    @Test("The epoch change is an entry, so the link is durable and folds like anything else")
    func epochChangeIsAnEntry() throws {
        let room = RoomID()
        let (chain, founding) = EpochChain.create(room: room)
        var author = Author(chain: chain)

        let advanced = try EpochChain.advance(from: founding, at: .initial, room: room)
        let payload = try Payload.epochChange(advanced.link)
        let entry = try author.append(payload, at: start, room: room)

        #expect(entry.payload.epoch == EpochNumber.initial)

        let opened = try #require(entry.opened(using: chain))
        #expect(opened.type == PayloadType.epochChange)
        #expect(try opened.decode(EpochChangeBody.self).link == advanced.link)
    }
}
