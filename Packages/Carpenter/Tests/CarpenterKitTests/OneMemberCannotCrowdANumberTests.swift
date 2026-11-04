@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("One member cannot fill a number so another member's key at it is refused", .serialized, .tags(.crypto))
struct OneMemberCannotCrowdANumberTests {
    @Test("Keys one member logged for a number leave room for another member's key at the same number")
    func anotherMembersKeyIsStillHeld() async throws {
        let t = try await RoomOfThree.make()
        let current = try #require(t.key(of: t.sam))
        let base = try #require(t.sam.chains[t.room]).secret(for: current)
        let samToCarol = try #require(t.sam.pairwiseSecret(with: t.carolID))
        var grants: [EpochGrant] = []
        for _ in 0...EpochChain.mostRivals {
            let (secret, link) = try EpochChain.advance(from: base, at: current, room: t.room)
            try await t.sam.append(
                try Payload.epochChange(link, heads: t.sam.lastEntries(in: t.room), under: secret), to: t.room)
            grants.append(
                try EpochGrant.issue(
                    secret, at: current.next, in: t.room, link: link, to: samToCarol,
                    devices: t.sam.deviceRecipients(of: t.carolID)
                ).signed(by: try #require(t.sam.enrolment?.device), from: t.samID, to: t.carolID))
        }
        try await t.sam.sync(through: t.mailbox, media: t.mailbox)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        let carolToSam = try #require(t.carol.pairwiseSecret(with: t.samID))
        for grant in grants {
            try await t.carol.adopt(
                grant, from: Peer(secret: carolToSam, them: t.samID, me: t.carolID), storedAt: .distantFuture)
        }

        let alicesBase = try #require(t.alice.chains[t.room]).secret(for: current)
        let (alices, link) = try EpochChain.advance(from: alicesBase, at: current, room: t.room)
        try await t.alice.append(
            try Payload.epochChange(link, heads: t.alice.lastEntries(in: t.room), under: alices), to: t.room)
        try await t.alice.sync(through: t.mailbox, media: t.mailbox)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        let grant = try EpochGrant.issue(
            alices, at: current.next, in: t.room, link: link,
            to: try #require(t.alice.pairwiseSecret(with: t.carolID)), devices: t.alice.deviceRecipients(of: t.carolID)
        ).signed(by: try #require(t.alice.enrolment?.device), from: t.aliceID, to: t.carolID)
        let carolToAlice = try #require(t.carol.pairwiseSecret(with: t.aliceID))
        try await t.carol.adopt(
            grant, from: Peer(secret: carolToAlice, them: t.aliceID, me: t.carolID), storedAt: .distantFuture)

        let held = Set(try #require(t.carol.chains[t.room]).heldSecrets(at: current.next))
        #expect(
            held.contains(alices),
            "one member logged \(EpochChain.mostRivals + 1) keys for a number and another member's key there was refused")
    }
}

@Suite("How many keys one person can put beside a number")
struct HowManyKeysOnePersonAddsTests {
    private let room = RoomID()
    private let next = EpochNumber.initial.next

    private func chain() -> (chain: EpochChain, first: EpochSecret) {
        let (chain, first) = EpochChain.create(room: room)
        return (chain, first)
    }

    private func made(_ count: Int, from first: EpochSecret) throws -> [EpochSecret] {
        try (0..<count).map { _ in try EpochChain.advance(from: first, at: .initial, room: room).secret }
    }

    @Test("A second key from one person is held only when the log records that same person making it")
    func theRecordHasToBeTheGivers() throws {
        var (chain, first) = chain()
        let (zed, alice) = (Identity.generate().id, Identity.generate().id)
        let keys = try made(3, from: first)
        chain.hold(keys[0], at: next, from: zed)
        chain.hold(keys[1], at: next, from: zed, recordedBy: { $0 == keys[1] ? [alice] : [] })
        chain.hold(keys[2], at: next, from: zed, recordedBy: { $0 == keys[2] ? [zed] : [] })

        #expect(Set(chain.heldSecrets(at: next)) == [keys[0], keys[2]], "somebody else's record let one person add a key")
    }

    @Test("One person can add only a few keys at a number, however many changes they log")
    func onePersonsAllowance() throws {
        var (chain, first) = chain()
        let zed = Identity.generate().id
        let keys = try made(EpochChain.mostKeysFromOnePerson + 3, from: first)
        for key in keys { chain.hold(key, at: next, from: zed, recordedBy: { _ in [zed] }) }

        #expect(chain.heldSecrets(at: next) == Array(keys.prefix(EpochChain.mostKeysFromOnePerson)))
    }

    @Test("Everybody's logged keys are held, even when together they pass the cap on unrecorded keys")
    func loggedKeysAreNotCrowdedOut() throws {
        var (chain, first) = chain()
        var makers: [EpochSecret: ParticipantID] = [:]
        var everyone: [EpochSecret] = []
        for _ in 0...(EpochChain.mostRivals / EpochChain.mostKeysFromOnePerson) {
            let person = Identity.generate().id
            let keys = try made(EpochChain.mostKeysFromOnePerson, from: first)
            for key in keys {
                makers[key] = person
                chain.hold(key, at: next, from: person, recordedBy: { makers[$0].map { [$0] } ?? [] })
            }
            everyone += keys
        }

        #expect(everyone.count > EpochChain.mostRivals + 1)
        #expect(Set(chain.heldSecrets(at: next)) == Set(everyone))
    }

    @Test("After a relaunch the keys a person logged still count against them, and every key comes back")
    func aRelaunchForgetsNothing() throws {
        var (before, first) = chain()
        let zed = Identity.generate().id
        let keys = try made(EpochChain.mostKeysFromOnePerson + 1, from: first)
        let records = { (key: EpochSecret) -> Set<ParticipantID> in [zed] }
        for key in keys.dropLast() { before.hold(key, at: next, from: zed, recordedBy: records) }

        var after = EpochChain.create(room: room).chain
        after.restore(before.heldSecrets(at: next), at: next)
        #expect(after.heldSecrets(at: next) == before.heldSecrets(at: next))
        after.hold(keys[keys.count - 1], at: next, from: zed, recordedBy: records)
        #expect(!after.heldSecrets(at: next).contains(keys[keys.count - 1]), "a relaunch gave one person a fresh allowance")
    }
}
