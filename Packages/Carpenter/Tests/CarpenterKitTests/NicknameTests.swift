@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A name of your own for somebody", .serialized)
struct NicknameTests {
    private func joined() async throws -> (alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox, room: ConversationID) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle(alice, bob, mailbox)
        return (alice, bob, mailbox, room)
    }

    private func settle(_ a: AppSession, _ b: AppSession, _ mailbox: InMemoryMailbox) async throws {
        for _ in 0..<4 {
            try await a.sync(through: mailbox)
            try await b.sync(through: mailbox)
        }
    }

    @Test("A nickname beats a code and a shared name alike, whether or not names are shown")
    func nicknameWins() async throws {
        let (alice, bob, mailbox, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)

        #expect(bob.member(aliceID).isPlaceholder, "nothing shared, nothing shown")
        await bob.setNickname("Al", for: aliceID)
        #expect(bob.member(aliceID).displayName == "Al")
        #expect(bob.connections().first { $0.id == aliceID }?.person.displayName == "Al", "the picker and People use the same name")

        await alice.setSharesName(true)
        await bob.setShowsOthersNames(true)
        try await settle(alice, bob, mailbox)
        #expect(bob.member(aliceID).displayName == "Al", "the member's own word stands over what was shared")
        #expect(bob.sharedName(of: aliceID) == "Alice", "and the page can still say what they shared")

        await bob.setNickname(nil, for: aliceID)
        #expect(bob.member(aliceID).displayName == "Alice")
    }

    @Test("A nickname reaches only the member's own devices")
    func staysHome() async throws {
        let (alice, bob, mailbox, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)
        await alice.setShowsOthersNames(true)

        await bob.setNickname("Al", for: aliceID)
        try await settle(alice, bob, mailbox)
        #expect(alice.viewer.displayName == "Alice")
        #expect(alice.sharedName(of: bobID) == nil, "a nickname must never fold as a name Bob gave")
        #expect(alice.member(bobID).isPlaceholder)
    }

    @Test("A solo is titled by the nickname")
    func soloTitle() async throws {
        let (alice, bob, mailbox, _) = try await joined()
        let bobID = try #require(bob.enrolment?.identity.id)
        let solo = try await alice.startSolo(with: bobID)
        _ = try await alice.invite(joinerCode: bob.identityCode(), joining: solo, mailbox: nil)
        try await alice.sync(through: mailbox)

        await alice.setNickname("Bobby", for: bobID)
        #expect(alice.rooms.first { $0.id == solo }?.name == "Bobby")
        #expect(alice.rooms.first { $0.id == solo }?.partner == bobID)
    }

    @Test("A nickname survives a relaunch")
    func survivesRelaunch() async throws {
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "nickname-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let other = ParticipantID(rawValue: WideID.of([1, 2, 3, 4, 5, 6]))

        let session = TestSession.make(keychain: keychain, at: directory)
        await session.load()
        try await session.createIdentity(displayName: "Alice")
        await session.setNickname("Rob", for: other)

        let relaunched = TestSession.make(keychain: keychain, at: directory)
        await relaunched.load()
        #expect(relaunched.nickname(for: other) == "Rob")
        #expect(relaunched.member(other).displayName == "Rob")
    }
}

@Suite("Photos kept for other people")
struct PersonAvatarStoreTests {
    @Test("A photo is filed by the whole identifier and comes back for it alone")
    func roundTrip() throws {
        let directory = URL.temporaryDirectory.appending(path: "people-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersonAvatarStore(directory: directory)
        let robin = ParticipantID(rawValue: WideID.of([0xA4, 0x1F, 0x2C, 0x91]))
        let sam = ParticipantID(rawValue: WideID.of([0xA4, 0x1F, 0x2C, 0x92]))

        #expect(store.loadAll().isEmpty)
        try store.save(Data([1, 2, 3]), for: robin)
        try store.save(Data([4, 5, 6]), for: sam)
        #expect(store.load(for: robin) == Data([1, 2, 3]))
        #expect(store.load(for: sam) == Data([4, 5, 6]))
        #expect(store.loadAll() == [robin: Data([1, 2, 3]), sam: Data([4, 5, 6])])

        try store.remove(for: robin)
        #expect(store.load(for: robin) == nil)
        #expect(store.loadAll() == [sam: Data([4, 5, 6])])

        try store.removeAll()
        #expect(store.loadAll().isEmpty)
    }

    @Test("The photo this member chose and the one somebody shared are two files, and neither touches the other")
    func chosenAndSharedAreApart() throws {
        let directory = URL.temporaryDirectory.appending(path: "people-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersonAvatarStore(directory: directory)
        let robin = ParticipantID(rawValue: WideID.of([0xA4, 0x1F, 0x2C, 0x91]))
        let first = AttachmentID()

        try store.save(Data([1]), for: robin)
        try store.saveShared(Data([2]), for: robin, attachment: first)
        #expect(store.load(for: robin) == Data([1]))
        #expect(store.loadShared(for: robin) == Data([2]))
        #expect(store.sharedAttachment(for: robin) == first)

        try store.removeShared(for: robin)
        #expect(store.loadShared(for: robin) == nil)
        #expect(store.load(for: robin) == Data([1]), "a takedown must never cost the member their own choice")

        let second = AttachmentID()
        try store.saveShared(Data([3]), for: robin, attachment: second)
        try store.remove(for: robin)
        #expect(store.load(for: robin) == nil)
        #expect(store.loadShared(for: robin) == Data([3]))
        #expect(store.sharedAttachment(for: robin) == second)
        #expect(store.loadAll().isEmpty, "the chosen list does not list shared photos")
        #expect(store.loadAllShared() == [robin: Data([3])])
    }
}
