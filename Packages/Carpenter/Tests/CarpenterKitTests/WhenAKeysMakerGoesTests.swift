@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("When the member who made a room's newest key goes, no phone drops back to a key somebody removed holds", .serialized)
struct WhenAKeysMakerGoesTests {
    private struct RoomOfFour {
        let three: RoomOfThree
        let dave: AppSession
        let carolsKey: TrustedKey

    }

    private func roomWhereCarolRemovedDave() async throws -> RoomOfFour {
        let t = try await RoomOfThree.make()
        let dave = TestSession.make()
        await dave.load()
        try await dave.createIdentity(displayName: "Dave")
        try await join(dave, into: t.room, of: t.alice, through: t.mailbox)
        try await t.settle()
        try #require(t.alice.roster(of: t.room).members.count == 4, "precondition: four members")

        try await t.carol.remove(dave.enrolment!.identity.id, from: t.room)
        try await t.settle()
        let carolsKey = try #require(t.carol.writingKey(of: t.room))
        try #require(carolsKey.maker == t.carolID, "precondition: the newest key is Carol's")
        for session in [t.alice, t.sam] {
            try #require(session.writingKey(of: t.room)?.secret == carolsKey.secret, "precondition: everybody took it")
        }
        return RoomOfFour(three: t, dave: dave, carolsKey: carolsKey)
    }

    private func lastEntry(by session: AppSession, in room: RoomID) throws -> Entry {
        let me = try #require(session.enrolment?.identity.id)
        return try #require(session.replica.allEntries.last { $0.author == me && $0.room == room })
    }

    @Test("A member who leaves on their own leaves their key counting, so nobody writes under one Dave holds")
    func aKeyOutlivesItsMakerLeaving() async throws {
        let r = try await roomWhereCarolRemovedDave()
        let t = r.three

        try await t.carol.leave(t.room)
        try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        try await t.sam.sync(through: t.mailbox, media: t.mailbox)
        try #require(t.sam.roster(of: t.room).departure(of: t.carolID) != nil, "precondition: Sam heard Carol leave")

        #expect(t.sam.writingKey(of: t.room)?.secret == r.carolsKey.secret, "Sam dropped back to an older key")
        try await t.sam.send("after Carol left", to: t.room)
        let sent = try lastEntry(by: t.sam, in: t.room)
        #expect(sent.opened(using: try #require(r.dave.chains[t.room])) == nil, "Dave, removed earlier, reads Sam")

        try await t.settle()
        #expect(
            t.alice.writingKey(of: t.room)?.epoch == r.carolsKey.epoch.next,
            "the rotation that answers Carol leaving started from an older key than hers")
    }

    @Test("A phone that hears its key's maker was removed before the remover's key arrives makes a key rather than drop back")
    func aPhoneInTheGapMakesItsOwnKey() async throws {
        let r = try await roomWhereCarolRemovedDave()
        let t = r.three

        let before = Set(t.alice.replica.allEntries.map(\.hash))
        try await t.alice.remove(t.carolID, from: t.room)
        let removal = try #require(
            t.alice.replica.allEntries.filter { !before.contains($0.hash) && $0.room == t.room }.min { $0.seq < $1.seq })
        var heard = t.sam.replica
        try heard.integrate(removal)
        t.sam.replica = heard
        try #require(t.sam.roster(of: t.room).removal(of: t.carolID) != nil, "precondition: Sam heard Carol's removal")
        try #require(t.sam.writingKey(of: t.room)?.secret != r.carolsKey.secret, "precondition: Carol's key stopped counting")

        try await t.sam.send("between the removal and the key", to: t.room)

        let sent = try lastEntry(by: t.sam, in: t.room)
        #expect(sent.opened(using: try #require(r.dave.chains[t.room])) == nil, "Dave, removed earlier, reads Sam")
        #expect(sent.opened(using: try #require(t.carol.chains[t.room])) == nil, "Carol, just removed, reads Sam")
        #expect(sent.opened(using: try #require(t.sam.chains[t.room])) != nil)

        try await t.settle()
        #expect(
            t.alice.messages(in: t.room).contains { $0.body == "between the removal and the key" },
            "Alice could not read what Sam wrote under the key he made")
        #expect(t.sam.writingKey(of: t.room)?.secret == t.alice.writingKey(of: t.room)?.secret)
    }

    @Test("A phone whose newest key is simply waiting on its record does not make a key")
    func noRemovalMeansNoNewKey() async throws {
        let r = try await roomWhereCarolRemovedDave()
        let t = r.three
        let held = t.sam.chains[t.room]?.heldKeyCount

        try await t.sam.send("an ordinary day", to: t.room)

        #expect(t.sam.chains[t.room]?.heldKeyCount == held, "Sam made a key nobody's removal called for")
    }
}
