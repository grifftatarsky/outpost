import Foundation
import Testing

@testable import CarpenterApp
@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Remembering what has been opened")
@MainActor
struct OpenedPayloadsTests {
    private func sessionWithAMessage() async throws -> (AppSession, RoomID, Entry) {
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let room = try await alice.createRoom(named: "Kitchen")
        try await alice.send("hello", to: room)
        let entry = try #require(alice.replica.allEntries.first { $0.room == room && alice.entryOpener()($0)?.type == .post })
        return (alice, room, entry)
    }

    @Test("An entry opens the same way the second time, from what was remembered")
    func openedEntriesStayOpen() async throws {
        let (alice, _, entry) = try await sessionWithAMessage()
        let first = alice.entryOpener()(entry)
        #expect(first != nil)
        #expect(alice.openedPayloads[entry.hash] == first)
        #expect(alice.entryOpener()(entry) == first)
    }

    @Test("Losing a room's keys loses what they opened")
    func losingTheChainForgets() async throws {
        let (alice, room, entry) = try await sessionWithAMessage()
        #expect(alice.entryOpener()(entry) != nil)

        alice.chains[room] = nil

        #expect(alice.openedPayloads[entry.hash] == nil)
        #expect(alice.entryOpener()(entry) == nil)
    }

    @Test("A room's chain rebuilt with fewer keys loses what the missing keys opened")
    func narrowingTheChainForgets() async throws {
        let (alice, room, entry) = try await sessionWithAMessage()
        #expect(alice.entryOpener()(entry) != nil)

        alice.chains[room] = EpochChain(room: room)

        #expect(alice.entryOpener()(entry) == nil)
    }

    @Test("Learning more keys keeps what was already opened")
    func addingKeysKeeps() async throws {
        let (alice, _, entry) = try await sessionWithAMessage()
        let opened = alice.entryOpener()(entry)
        let other = try await alice.createRoom(named: "Hangar")

        #expect(alice.chains[other] != nil)
        #expect(alice.openedPayloads[entry.hash] == opened)
    }

    private func drawn(_ entry: Entry, in alice: AppSession) -> RenderedContent? {
        alice.projection.rendered.first { $0.id == entry.hash }?.content
    }

    @Test("What an entry shows is read once, and a rebuild draws it from what was remembered")
    func aRebuildReusesWhatWasRead() async throws {
        let (alice, _, entry) = try await sessionWithAMessage()
        #expect(drawn(entry, in: alice) == .text("hello"))
        let remembered = try #require(alice.openedPayloads[step: entry.hash])

        alice.logChanged()

        #expect(drawn(entry, in: alice) == .text("hello"))
        guard case .shows(let made) = remembered, case .shows(let again) = alice.openedPayloads[step: entry.hash] else {
            Issue.record("the post was not remembered as something it shows")
            return
        }
        #expect(made == again)
    }

    @Test("Losing a room's keys forgets what its entries showed")
    func losingTheChainForgetsWhatWasShown() async throws {
        let (alice, room, entry) = try await sessionWithAMessage()
        #expect(drawn(entry, in: alice) == .text("hello"))

        alice.chains[room] = EpochChain(room: room)

        #expect(alice.openedPayloads[step: entry.hash] == nil)
        #expect(drawn(entry, in: alice) == .sealed)
    }

    @Test("An entry drawn sealed is read again when its key arrives")
    func aSealedEntryOpensWhenTheKeyComes() async throws {
        let (alice, room, entry) = try await sessionWithAMessage()
        let chain = try #require(alice.chains[room])
        alice.chains[room] = EpochChain(room: room)
        #expect(drawn(entry, in: alice) == .sealed)

        alice.chains[room] = chain

        #expect(
            drawn(entry, in: alice) == .text("hello"),
            "the sealed placeholder was remembered and outlived the key that opens it")
    }
}
