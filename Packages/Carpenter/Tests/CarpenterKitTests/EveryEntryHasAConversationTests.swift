import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@MainActor
@Suite("Every entry says which conversation it is in", .serialized)
struct EveryEntryHasAConversationTests {
    private func settle(_ sessions: [AppSession], _ mailbox: InMemoryMailbox, rounds: Int = 4) async throws {
        for _ in 0..<rounds {
            for session in sessions { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    @Test("A post on your own Outpost is in your Outpost, by name")
    func ownPostNamesItsOutpost() async throws {
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let aliceID = try #require(alice.enrolment?.identity.id)

        try await alice.send("the kite is up", to: try #require(alice.ownOutpost))

        let written = try #require(alice.replica.allEntries.last { $0.author == aliceID })
        #expect(written.conversation == .outpost(aliceID))
        #expect(written.isOnOwnOutpost)
    }

    @Test("Nobody can post straight onto somebody else's Outpost")
    func anotherOutpostRefusesAPost() async throws {
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let bobID = try #require(bob.enrolment?.identity.id)
        let before = alice.replica.allEntries.count

        await #expect(throws: AppSessionError.cannotWriteThere) {
            try await alice.send("I live here now", to: .outpost(bobID))
        }
        #expect(alice.replica.allEntries.count == before, "the refused post was written anyway")
    }

    @Test("No path can mint a key for somebody else's Outpost")
    func noKeyIsMintedForAnotherOutpost() async throws {
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let bobID = try #require(bob.enrolment?.identity.id)

        await #expect(throws: AppSessionError.cannotWriteThere) {
            try await alice.append(try Payload.post("mine now"), to: .outpost(bobID))
        }
        #expect(alice.chains[.outpost(bobID)] == nil, "a key for Bob's Outpost was made on Alice's device")
    }

    @Test("Every entry opens under the key of the conversation it names")
    func theEnvelopeAndTheSealAgree() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        for session in [alice, bob] { await session.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let solo = try await alice.createRoom(named: "Just us", kind: .solo)
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await settle([alice, bob], mailbox)

        try await alice.send("in the room", to: room)
        try await alice.send("in the solo", to: solo)
        try await alice.send("on the wall", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], mailbox)

        #expect(room.kind == .room)
        #expect(solo.kind == .solo)

        let mine = alice.replica.allEntries.filter { $0.author == alice.enrolment?.identity.id }
        #expect(mine.count > 3, "this test asserted almost nothing")
        for entry in mine {
            let chain = try #require(
                alice.chains[entry.conversation],
                "an entry names \(entry.conversation.stableName) and there is no key for it")
            #expect(
                entry.opened(using: chain) != nil,
                "an entry in \(entry.conversation.stableName) was sealed under some other key")
        }
    }

    @Test("A solo is named a solo from the moment it exists")
    func aSoloKnowsItIsASolo() async throws {
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")

        let solo = try await alice.createRoom(named: "Just us", kind: .solo)
        let room = try await alice.createRoom(named: "Everyone")

        #expect(solo.kind == .solo)
        #expect(room.kind == .room)
        #expect(solo.owner == nil && room.owner == nil)
    }
}
