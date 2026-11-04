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
