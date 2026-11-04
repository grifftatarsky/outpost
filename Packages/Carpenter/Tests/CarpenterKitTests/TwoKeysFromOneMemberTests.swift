@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("A second key from one member for one number is held when the room's log records it")
struct TwoKeysFromOneMemberChainTests {
    @Test("A second key from the same giver is held when its record is in the log, and refused when it is not")
    func aRecordedSecondKeyIsHeld() throws {
        let room = RoomID()
        let (created, first) = EpochChain.create(room: room)
        var chain = created
        let next = EpochNumber.initial.next
        let zed = Identity.generate().id
        let (fromOnePhone, _) = try EpochChain.advance(from: first, at: .initial, room: room)
        let (fromTheOther, _) = try EpochChain.advance(from: first, at: .initial, room: room)
        let unrecorded = EpochSecret.random()

        chain.hold(fromOnePhone, at: next, from: zed)
        chain.hold(unrecorded, at: next, from: zed)
        chain.hold(fromTheOther, at: next, from: zed, recordedBy: { $0 == fromTheOther ? [zed] : [] })

        #expect(Set(chain.heldSecrets(at: next)) == [fromOnePhone, fromTheOther])
    }
}

@MainActor
@Suite("Two keys one member made for one number both reach everybody", .serialized)
struct TwoKeysFromOneMemberTests {
    @Test("When a member's two phones rotate at once, the rest of the room takes both keys")
    func bothKeysAreRead() async throws {
        let t = try await RoomOfThree.make()
        let current = try #require(t.key(of: t.sam))
        let chain = try #require(t.sam.chains[t.room])
        let base = try chain.secret(for: current)

        var made: [EpochSecret] = []
        for _ in 0..<2 {
            let (secret, link) = try EpochChain.advance(from: base, at: current, room: t.room)
            try await t.sam.append(
                try Payload.epochChange(link, heads: t.sam.lastEntries(in: t.room), under: secret), to: t.room)
            made.append(secret)
            try await t.sam.sync(through: t.mailbox, media: t.mailbox)
            try await t.carol.sync(through: t.mailbox, media: t.mailbox)
            let grant = try EpochGrant.issue(
                secret, at: current.next, in: t.room, link: link,
                to: try #require(t.sam.pairwiseSecret(with: t.carolID)), devices: t.sam.deviceRecipients(of: t.carolID)
            ).signed(by: try #require(t.sam.enrolment?.device), from: t.samID, to: t.carolID)
            let pairwise = try #require(t.carol.pairwiseSecret(with: t.samID))
            try await t.carol.adopt(
                grant, from: Peer(secret: pairwise, them: t.samID, me: t.carolID), storedAt: .distantFuture)
        }

        let held = Set(try #require(t.carol.chains[t.room]).heldSecrets(at: current.next))
        #expect(held.isSuperset(of: made), "the second key one member made for a number was refused")
    }

    @Test("A key made up without a record is still refused beside one from the same member")
    func anUnrecordedSecondKeyIsRefused() async throws {
        let t = try await RoomOfThree.make()
        let current = try #require(t.key(of: t.sam))
        let base = try #require(t.sam.chains[t.room]).secret(for: current)
        var made: [EpochSecret] = []
        for _ in 0..<2 {
            let (secret, link) = try EpochChain.advance(from: base, at: current, room: t.room)
            made.append(secret)
            let grant = try EpochGrant.issue(
                secret, at: current.next, in: t.room, link: link,
                to: try #require(t.sam.pairwiseSecret(with: t.carolID)), devices: t.sam.deviceRecipients(of: t.carolID)
            ).signed(by: try #require(t.sam.enrolment?.device), from: t.samID, to: t.carolID)
            let pairwise = try #require(t.carol.pairwiseSecret(with: t.samID))
            try await t.carol.adopt(
                grant, from: Peer(secret: pairwise, them: t.samID, me: t.carolID), storedAt: .distantFuture)
        }

        let held = Set(try #require(t.carol.chains[t.room]).heldSecrets(at: current.next))
        #expect(held.contains(made[0]) && !held.contains(made[1]))
    }
}
