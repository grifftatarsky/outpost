@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

actor RefusingEpochKeychainStore: KeychainStore {
    struct Refused: Error {}

    private let real = InMemoryKeychainStore()
    private var refusesNextEpoch = false

    func refuseTheNextEpochSecret() { refusesNextEpoch = true }

    func data(for key: KeychainKey) async throws -> Data? { try await real.data(for: key) }

    func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws {
        if refusesNextEpoch, key.rawValue.hasPrefix("epoch.") {
            refusesNextEpoch = false
            throw Refused()
        }
        try await real.set(data, for: key, scope: scope)
    }

    func remove(_ key: KeychainKey) async throws { try await real.remove(key) }
    func removeAll() async throws { try await real.removeAll() }
}

@MainActor
@Suite("A removal that is cut off halfway is finished after a relaunch", .serialized)
struct RemovalSurvivesACrashTests {
    private func session(
        in directory: URL, keychain: any KeychainStore, log: (any LogStore)? = nil
    ) -> AppSession {
        AppSession(
            storage: SessionStorage(
                keychain: keychain,
                log: log ?? FileLogStore(url: directory.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json")),
                media: MemoryMediaStore()),
            clock: TestClock(now: TestSession.now))
    }

    private func member(_ name: String) async throws -> AppSession {
        let session = TestSession.make()
        await session.load()
        try await session.createIdentity(displayName: name)
        return session
    }

    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func admit(
        _ joiner: AppSession, to room: ConversationID, by inviter: AppSession,
        alongside everyone: [AppSession], through mailbox: InMemoryMailbox
    ) async throws {
        let invite = try await inviter.invite(
            joinerCode: joiner.identityCode(), joining: room, mailbox: nil)
        try await joiner.redeem(inviteCode: try invite.encoded())
        try await settle(everyone + [joiner], through: mailbox)
    }

    private struct Room {
        let mailbox: InMemoryMailbox
        let directory: URL
        let alice: AppSession
        let bob: AppSession
        let carol: AppSession
        let id: ConversationID
        let epochBefore: EpochNumber
    }

    private static func directory() throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-crash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func roomOfThree(
        in directory: URL, keychain: any KeychainStore, log: (any LogStore)? = nil
    ) async throws -> Room {
        let mailbox = InMemoryMailbox()

        let alice = session(in: directory, keychain: keychain, log: log)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let bob = try await member("Bob")
        let carol = try await member("Carol")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await admit(bob, to: room, by: alice, alongside: [alice], through: mailbox)
        try await admit(carol, to: room, by: alice, alongside: [alice, bob], through: mailbox)
        try await alice.send("while all three", to: room)
        try await settle([alice, bob, carol], through: mailbox)
        #expect(carol.messages(in: room).map(\.body).contains("while all three"))

        let before = try #require(alice.chains[room]?.highestKnownEpoch)
        return Room(
            mailbox: mailbox, directory: directory, alice: alice, bob: bob, carol: carol, id: room,
            epochBefore: before)
    }

    private func expectTheRemovalFinished(
        _ room: Room, relaunched alice: AppSession, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let carolID = try #require(room.carol.enrolment?.identity.id)
        let everyone = [alice, room.bob, room.carol]
        try await settle(everyone, through: room.mailbox)

        for device in [alice, room.bob] {
            #expect(
                !device.roster(of: room.id).members.contains(carolID),
                "a device that stayed still counts Carol in", sourceLocation: sourceLocation)
        }

        let turned = try #require(alice.chains[room.id]?.highestKnownEpoch)
        #expect(
            turned > room.epochBefore,
            "every device agrees Carol is out, and the key she holds is still the room's key",
            sourceLocation: sourceLocation)

        try await alice.send("after Carol went", to: room.id)
        try await settle(everyone, through: room.mailbox)

        #expect(
            room.bob.messages(in: room.id).map(\.body).contains("after Carol went"),
            "the turned key never reached the member who stayed", sourceLocation: sourceLocation)
        #expect(
            room.carol.chains[room.id]?.knownEpochs.contains(turned) != true,
            "the removed member holds the key the room turned to", sourceLocation: sourceLocation)
        #expect(
            !room.carol.messages(in: room.id).map(\.body).contains("after Carol went"),
            "a removed member went on reading the room", sourceLocation: sourceLocation)
        #expect(
            room.carol.messages(in: room.id).map(\.body).contains("while all three"),
            "removal reached backwards into what Carol already held", sourceLocation: sourceLocation)
    }

    @Test("Cut off after the removal is written and before the key turns")
    func cutOffBeforeTheTurn() async throws {
        let keychain = InMemoryKeychainStore()
        let directory = try Self.directory()
        let log = RefusingLogStore(url: directory.appending(path: "log.carpenter"))
        let room = try await roomOfThree(in: directory, keychain: keychain, log: log)
        let carolID = try #require(room.carol.enrolment?.identity.id)

        await log.refuseAppend(afterLetting: 1)
        await #expect(throws: (any Error).self) { try await room.alice.remove(carolID, from: room.id) }

        let relaunched = session(in: room.directory, keychain: keychain)
        await relaunched.load()
        #expect(
            !relaunched.roster(of: room.id).members.contains(carolID),
            "precondition: the removal itself reached the disk")

        try await expectTheRemovalFinished(room, relaunched: relaunched)
    }

    @Test("Cut off after the key turn is written and before its secret is kept")
    func cutOffBeforeTheSecretIsKept() async throws {
        let keychain = RefusingEpochKeychainStore()
        let room = try await roomOfThree(in: try Self.directory(), keychain: keychain)
        let carolID = try #require(room.carol.enrolment?.identity.id)

        await keychain.refuseTheNextEpochSecret()
        await #expect(throws: (any Error).self) { try await room.alice.remove(carolID, from: room.id) }

        let relaunched = session(in: room.directory, keychain: keychain)
        await relaunched.load()
        #expect(!relaunched.roster(of: room.id).members.contains(carolID))

        try await expectTheRemovalFinished(room, relaunched: relaunched)
    }
}
