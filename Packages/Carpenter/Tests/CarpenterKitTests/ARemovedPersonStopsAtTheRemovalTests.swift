import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("A removed person's words stop where the removal saw them")
struct ARemovedPersonStopsAtTheRemovalTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func seeing(_ key: FeedKey, seq: UInt64) -> VectorClock {
        var clock = VectorClock()
        clock.observe(key, seq: seq)
        return clock
    }

    private func room() throws -> (alice: Author, sam: Author, room: RoomID, entries: [Entry]) {
        let chain = EpochChain.create(room: RoomID())
        var alice = Author(chain: chain.chain)
        let sam = Author(chain: chain.chain)
        let room = chain.chain.room
        var entries: [Entry] = []
        entries.append(try alice.append(try Payload.roomProfile(name: "Hangar 7"), at: start, room: room))
        let invite = try TestInvite.issue(
            joining: room, joinerKeys: sam.identity.publicKeys, by: alice.identity, at: start)
        entries.append(
            try alice.append(try Payload.joinRequest(invite), at: start.addingTimeInterval(1), room: room))
        entries.append(
            try alice.append(
                try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: sam.identity)),
                at: start.addingTimeInterval(2), room: room))
        return (alice, sam, room, entries)
    }

    private func out(_ entries: [Entry], viewer: ParticipantID, chain: EpochChain, room: RoomID) -> Set<EntryHash> {
        let projected = Projection(viewer: viewer, rendered: LogRenderer.render(entries, using: chain))
        return projected.outOfRoom(in: room, opening: { rendered in
            entries.first { $0.hash == rendered.id }?.opened(using: chain)
        })
    }

    @Test("Something written alongside the removal, dated long before it, does not count")
    func aConcurrentBackdatedEntryIsOut() throws {
        var (alice, sam, room, entries) = try room()
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id), at: start.addingTimeInterval(100), room: room)
        entries.append(removal)
        let backdated = try sam.append(
            try Payload.post("I was never removed"), at: start.addingTimeInterval(-3600), room: room)
        entries.append(backdated)

        #expect(
            out(entries, viewer: alice.identity.id, chain: alice.chain, room: room).contains(backdated.hash),
            "an entry the removal never saw counted because its author dated it early")
    }

    @Test("What the remover had received before removing them stays")
    func whatTheRemovalSawStays() throws {
        var (alice, sam, room, entries) = try room()
        let before = try sam.append(try Payload.post("said in time"), at: start.addingTimeInterval(10), room: room)
        entries.append(before)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id), clock: seeing(sam.feedKey, seq: before.seq),
            at: start.addingTimeInterval(20), room: room)
        entries.append(removal)

        #expect(!out(entries, viewer: alice.identity.id, chain: alice.chain, room: room).contains(before.hash))
    }

    @Test("Something written before the removal that had not reached the remover is dropped")
    func whatWasInTransitIsDropped() throws {
        var (alice, sam, room, entries) = try room()
        let seen = try sam.append(try Payload.post("arrived"), at: start.addingTimeInterval(10), room: room)
        let inTransit = try sam.append(
            try Payload.post("still travelling"), at: start.addingTimeInterval(15), room: room)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id), clock: seeing(sam.feedKey, seq: seen.seq),
            at: start.addingTimeInterval(20), room: room)
        entries += [seen, removal, inTransit]

        let gone = out(entries, viewer: alice.identity.id, chain: alice.chain, room: room)
        #expect(!gone.contains(seen.hash))
        #expect(gone.contains(inTransit.hash), "a message the remover never received came back in")
    }

    @Test("Every member draws the same line, whatever order the entries reached them in")
    func everyMemberAgrees() throws {
        var (alice, sam, room, entries) = try room()
        let seen = try sam.append(try Payload.post("arrived"), at: start.addingTimeInterval(10), room: room)
        let removal = try alice.append(
            try Payload.removal(of: sam.identity.id), clock: seeing(sam.feedKey, seq: seen.seq),
            at: start.addingTimeInterval(20), room: room)
        let late = try sam.append(try Payload.post("late"), at: start.addingTimeInterval(-50), room: room)
        entries += [seen, removal, late]

        let carol = Identity.generate().id
        let first = out(entries, viewer: alice.identity.id, chain: alice.chain, room: room)
        for order in [entries.reversed(), entries.shuffled(), entries.shuffled()] {
            #expect(out(Array(order), viewer: carol, chain: alice.chain, room: room) == first)
        }
        #expect(first == [late.hash])
    }
}

@Suite("A removed device's words stop where its removal saw them")
struct ARemovedDeviceStopsAtTheCutoffTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let identity = Identity.generate()
    private let phone = DeviceKeys.generate()
    private let stolen = DeviceKeys.generate()

    private func registry(cutoff: UInt64?) throws -> DeviceRegistry {
        var registry = DeviceRegistry(identity: identity.publicKeys)
        try registry.admit(DeviceCertificate.recovered(for: phone, by: identity, at: start), storedAt: start)
        try registry.admit(
            DeviceCertificate.issue(for: stolen, by: identity, at: start + 10, approvedBy: phone),
            storedAt: start + 10)
        try registry.revoke(
            DeviceRevocation.issue(for: stolen.id, by: identity, at: start + 1000, from: phone, cutoff: cutoff),
            storedAt: start + 1000)
        return registry
    }

    @Test("Past the cutoff nothing counts, whatever date the device writes on it")
    func pastTheCutoffNothingCounts() throws {
        let registry = try registry(cutoff: 4)
        #expect(registry.isAuthorized(stolen.id, at: start + 500, seq: 4))
        #expect(!registry.isAuthorized(stolen.id, at: start + 500, seq: 5), "a backdated entry past the cutoff counted")
        #expect(!registry.isAuthorized(stolen.id, at: start + 11, seq: 900))
        #expect(registry.isAuthorized(stolen.id, at: start + 5000, seq: 3), "an entry the removal had seen was dropped")
    }

    @Test("Nothing counts from before the device was approved")
    func beforeApprovalNothingCounts() throws {
        #expect(!(try registry(cutoff: 4)).isAuthorized(stolen.id, at: start + 5, seq: 1))
    }

    @Test("A removal made before cutoffs existed still goes by its date")
    func anOlderRemovalGoesByDate() throws {
        let registry = try registry(cutoff: nil)
        #expect(registry.isAuthorized(stolen.id, at: start + 999, seq: 50))
        #expect(!registry.isAuthorized(stolen.id, at: start + 1001, seq: 1))
    }

    @Test("A replica refuses the stolen device's backdated entry past the cutoff, and keeps refusing it")
    func theReplicaRefuses() throws {
        var replica = Replica()
        replica.introduce(identity.publicKeys)
        try replica.admit(DeviceCertificate.recovered(for: phone, by: identity, at: start), storedAt: start)
        try replica.admit(
            DeviceCertificate.issue(for: stolen, by: identity, at: start + 10, approvedBy: phone), storedAt: start + 10)

        let chain = EpochChain.create(room: RoomID()).chain
        var head: Entry?
        var written: [Entry] = []
        for index in 0..<3 {
            let entry = try Entry.append(
                to: head, author: identity.id, device: stolen, clock: head?.clock ?? VectorClock(),
                wallTime: start + 20 + Double(index), room: nil, payload: try Payload.post("\(index)"),
                at: .initial, sealedWith: chain)
            head = entry
            written.append(entry)
        }
        try replica.integrate(written[0])
        try replica.integrate(written[1])
        try replica.revoke(
            DeviceRevocation.issue(for: stolen.id, by: identity, at: start + 1000, from: phone, cutoff: 2),
            storedAt: start + 1000)

        #expect(throws: (any Error).self, "an entry past the cutoff, dated before the removal, was taken") {
            try replica.integrate(written[2])
        }
        #expect(replica.refusesForever(written[2]))
        #expect(!replica.refusesForever(written[1]))
    }

    @Test("The cutoff is signed: changing it breaks the removal")
    func theCutoffIsSigned() throws {
        var revocation = try DeviceRevocation.issue(
            for: stolen.id, by: identity, at: start + 1000, from: phone, cutoff: 4)
        try revocation.verify(against: identity.publicKeys)
        revocation.cutoff = 900
        #expect(throws: (any Error).self) { try revocation.verify(against: identity.publicKeys) }
    }

    @Test("A removal without a cutoff signs the same bytes it always did")
    func theOldLayoutIsUnchanged() throws {
        let revocation = try DeviceRevocation.issue(for: stolen.id, by: identity, at: start + 1000, from: phone)
        let expected = CanonicalBytes.payload(
            domain: Domain.deviceRevocation,
            fields: [
                identity.id.rawValue, stolen.id.rawValue, CanonicalBytes.timestamp(start + 1000),
                Data("revoked-by".utf8), phone.id.rawValue,
            ])
        #expect(revocation.signingPayload == expected)
    }
}
