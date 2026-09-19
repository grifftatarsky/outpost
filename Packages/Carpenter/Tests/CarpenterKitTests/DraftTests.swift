@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("A seal for a draft")
struct DraftSealTests {
    private let room = RoomID()
    private let key = DraftSeal.newKey()

    @Test("A draft opens with its key in its room")
    func roundTrip() throws {
        let sealed = try DraftSeal.seal("half a thought about the mooring mast", in: room, with: key)
        #expect(DraftSeal.open(sealed, in: room, with: key) == "half a thought about the mooring mast")
    }

    @Test("A draft does not open in another room, under another key, or once a byte has changed")
    func refusals() throws {
        var sealed = try DraftSeal.seal("not yet", in: room, with: key)
        #expect(DraftSeal.open(sealed, in: RoomID(), with: key) == nil)
        #expect(DraftSeal.open(sealed, in: room, with: DraftSeal.newKey()) == nil)
        sealed[sealed.count - 1] ^= 1
        #expect(DraftSeal.open(sealed, in: room, with: key) == nil)
    }

    @Test("The sealed bytes do not carry the words")
    func unreadable() throws {
        let sealed = try DraftSeal.seal("the door code is 1930", in: room, with: key)
        #expect(sealed.range(of: Data("1930".utf8)) == nil)
    }
}

@MainActor
@Suite("A draft that survives", .serialized)
struct DraftTests {
    private func member(at directory: URL, keychain: any KeychainStore) async throws -> (AppSession, RoomID) {
        let session = TestSession.make(keychain: keychain, at: directory)
        await session.load()
        try await session.createIdentity(displayName: "Alice")
        let room = try await session.createRoom(named: "Hangar 7")
        return (session, room)
    }

    private func reopened(at directory: URL, keychain: any KeychainStore) async -> AppSession {
        let session = TestSession.make(keychain: keychain, at: directory)
        await session.load()
        return session
    }

    private func directory() -> URL {
        URL.temporaryDirectory.appending(path: "carpenter-drafts-\(UUID().uuidString)")
    }

    @Test("A draft is there after the app is closed and opened again")
    func survivesARelaunch() async throws {
        let place = directory()
        let keychain = InMemoryKeychainStore()
        let (alice, room) = try await member(at: place, keychain: keychain)

        await alice.keepDraft("remember to bring the gloves", in: room)

        let again = await reopened(at: place, keychain: keychain)
        #expect(again.draft(in: room) == "remember to bring the gloves")
    }

    @Test("The state file holds the draft sealed, never the words")
    func sealedOnDisk() async throws {
        let place = directory()
        let keychain = InMemoryKeychainStore()
        let (alice, room) = try await member(at: place, keychain: keychain)

        await alice.keepDraft("the door code is 1930", in: room)

        let file = try Data(contentsOf: place.appending(path: "state.json"))
        #expect(file.range(of: Data("1930".utf8)) == nil, "a draft reached the disk readable")
        #expect(!file.isEmpty)
    }

    @Test("Without this device's key the draft does not open, and nothing else breaks")
    func anotherKeychainCannotRead() async throws {
        let place = directory()
        let keychain = InMemoryKeychainStore()
        let (alice, room) = try await member(at: place, keychain: keychain)
        await alice.keepDraft("only here", in: room)

        let stranger = InMemoryKeychainStore()
        for key in [IdentityStore.identityKey, IdentityStore.deviceKey] {
            if let data = try await keychain.data(for: key) {
                try await stranger.set(data, for: key, scope: .device)
            }
        }
        let copied = await reopened(at: place, keychain: stranger)
        #expect(copied.state == .ready)
        #expect(copied.draft(in: room).isEmpty)
    }

    @Test("Sending clears it: an empty draft is removed, from memory and from the disk")
    func emptyClears() async throws {
        let place = directory()
        let keychain = InMemoryKeychainStore()
        let (alice, room) = try await member(at: place, keychain: keychain)
        await alice.keepDraft("going", in: room)
        await alice.keepDraft("  \n", in: room)

        #expect(alice.draft(in: room).isEmpty)
        let again = await reopened(at: place, keychain: keychain)
        #expect(again.draft(in: room).isEmpty)
    }

    @Test("A reply that could not be sent from a banner joins the draft on a new line")
    func unsentReplyJoinsTheDraft() async throws {
        let place = directory()
        let keychain = InMemoryKeychainStore()
        let (alice, room) = try await member(at: place, keychain: keychain)
        await alice.keepDraft("I was writing this", in: room)

        #expect(await alice.keepUnsentReply("on my way", in: room))
        #expect(alice.draft(in: room) == "I was writing this\non my way")
        #expect(await alice.keepUnsentReply("anything", in: RoomID()) == false)
    }

    @Test("Two drafts kept at once make one key, not two")
    func oneKey() async throws {
        let keychain = CountingSets()
        let (alice, room) = try await member(at: directory(), keychain: keychain)
        let other = try await alice.createRoom(named: "Checks")
        alice.noteDraft("one", in: room)
        alice.noteDraft("two", in: other)
        async let first: Void = alice.sealDraft(in: room)
        async let second: Void = alice.sealDraft(in: other)
        _ = await (first, second)
        #expect(await keychain.sets(of: DraftSeal.key) == 1)
    }
}

private actor CountingSets: KeychainStore {
    private let inner = InMemoryKeychainStore()
    private var counts: [KeychainKey: Int] = [:]

    func sets(of key: KeychainKey) -> Int { counts[key, default: 0] }

    func data(for key: KeychainKey) async throws -> Data? { try await inner.data(for: key) }

    func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws {
        counts[key, default: 0] += 1
        try await inner.set(data, for: key, scope: scope)
    }

    func remove(_ key: KeychainKey) async throws { try await inner.remove(key) }

    func removeAll() async throws { try await inner.removeAll() }
}
