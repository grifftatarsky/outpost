import CryptoKit
import Foundation
import Testing

@testable import CarpenterApp
@testable import CarpenterKit
@testable import CarpenterKitTesting

@MainActor
@Suite("App session", .serialized)
struct AppSessionTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func storage() -> (SessionStorage, URL) {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-session-\(UUID().uuidString)")
        return (
            SessionStorage(
                keychain: InMemoryKeychainStore(),
                log: FileLogStore(url: directory.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json"))
            ),
            directory
        )
    }

    private func session(_ storage: SessionStorage) -> AppSession {
        AppSession(storage: storage, clock: TestClock(now: start))
    }

    @Test("A launch with nothing stored asks for an identity rather than inventing one")
    func firstLaunch() async {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        app.checkAccount(with: StubAccountRegistry(hasMember: false))
        await app.load()

        #expect(app.state == .checkingForRegistration)

        await app.settleRegistration(attempts: 1)

        #expect(app.state == .needsIdentity)
        #expect(app.rooms.isEmpty)
    }

    @Test("Creating an identity puts the member's name in the log")
    func createIdentity() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        await app.load()
        try await app.createIdentity(displayName: "Cassilda")

        #expect(app.state == .ready)
        #expect(app.viewer.displayName == "Cassilda")
    }

    @Test("An identity with no profile in the log asks for a name rather than going nameless")
    func identityWithoutProfile() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try await IdentityStore(keychain: storage.keychain).enrol()

        let app = session(storage)
        await app.load()
        #expect(app.state == .needsProfile)

        try await app.setDisplayName("Cassilda")

        #expect(app.state == .ready)
        #expect(app.viewer.displayName == "Cassilda")
    }

    @Test("A room appears in the list once it is named")
    func createRoom() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        await app.load()
        try await app.createIdentity(displayName: "Cassilda")
        try await app.createRoom(named: "Zeppelin Enthusiasts")

        #expect(app.rooms.map(\.name) == ["Zeppelin Enthusiasts"])
    }

    @Test("A sent message is readable back through the fold")
    func sendAndRead() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        await app.load()
        try await app.createIdentity(displayName: "Cassilda")
        let room = try await app.createRoom(named: "Zeppelin Enthusiasts")

        try await app.send("hydrogen, obviously", to: room)
        try await app.send("helium coward", to: room)

        let messages = app.messages(in: room)
        let allMine = messages.allSatisfy { $0.isMine }
        let allHers = messages.allSatisfy { $0.author.displayName == "Cassilda" }

        #expect(messages.map(\.body) == ["hydrogen, obviously", "helium coward"])
        #expect(allMine)
        #expect(allHers)
    }

    @Test("Empty text is not a message")
    func emptyMessagesAreRefused() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        await app.load()
        try await app.createIdentity(displayName: "Cassilda")
        let room = try await app.createRoom(named: "Hangar 7")

        try await app.send("   \n ", to: room)

        #expect(app.messages(in: room).isEmpty)
    }

    @Test("Everything survives a relaunch")
    func survivesRelaunch() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = session(storage)
        await first.load()
        try await first.createIdentity(displayName: "Cassilda")
        let room = try await first.createRoom(named: "Zeppelin Enthusiasts")
        try await first.send("a piano. inside a hydrogen balloon.", to: room)

        let second = session(storage)
        await second.load()

        #expect(second.state == .ready)
        #expect(second.viewer.displayName == "Cassilda")
        #expect(second.rooms.map(\.name) == ["Zeppelin Enthusiasts"])
        #expect(
            second.messages(in: room).map(\.body) == ["a piano. inside a hydrogen balloon."])
        #expect(second.lastLoad == .complete)
    }

    @Test("Messages written after a relaunch continue the same feed")
    func appendsAcrossLaunches() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = session(storage)
        await first.load()
        try await first.createIdentity(displayName: "Cassilda")
        let room = try await first.createRoom(named: "Hangar 7")
        try await first.send("before", to: room)

        let second = session(storage)
        await second.load()
        try await second.send("after", to: room)

        let third = session(storage)
        await third.load()

        #expect(third.messages(in: room).map(\.body) == ["before", "after"])
        #expect(!third.forks.contains { $0.feed.author == third.enrolment?.identity.id })
    }

    @Test("The Outpost is the feed with no room, and keeps profile entries out of it")
    func outpost() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        await app.load()
        try await app.createIdentity(displayName: "Cassilda")
        try await app.send("Naotalba is wrong about blimps.", to: nil)

        let posts = app.outpost()

        #expect(posts.map(\.body) == ["Naotalba is wrong about blimps."])
        #expect(!posts.contains { $0.body == "Cassilda" })
    }

    @Test("A comment answers a post and does not appear in the feed on its own")
    func comments() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        await app.load()
        try await app.createIdentity(displayName: "Cassilda")
        try await app.send("The word dirigible just means steerable.", to: nil)

        let post = try #require(app.feed().first)
        try await app.comment(on: post, text: "a balloon that made a decision")
        try await app.comment(on: post, text: "putting this on the masthead")

        #expect(app.feed().count == 1)
        #expect(app.feed().first?.commentCount == 2)
        #expect(
            app.comments(on: post).map(\.body)
                == ["a balloon that made a decision", "putting this on the masthead"])
    }

    @Test("A reaction reaches the post it was made on, without looking it up by time")
    func reactionsTargetTheEntry() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        await app.load()
        try await app.createIdentity(displayName: "Cassilda")
        try await app.send("hydrogen, obviously", to: nil)

        let post = try #require(app.feed().first)
        try await app.react(to: post, emoji: "🔥")

        let reacted = try #require(app.feed().first)
        #expect(reacted.reactions["🔥"]?.count == 1)

        try await app.react(to: reacted, emoji: nil)
        #expect(app.feed().first?.reactions.isEmpty == true)
    }

    @Test("Comments survive a relaunch with their post")
    func commentsPersist() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = session(storage)
        await first.load()
        try await first.createIdentity(displayName: "Cassilda")
        try await first.send("Naotalba is wrong about blimps.", to: nil)
        try await first.comment(on: try #require(first.feed().first), text: "he is not")

        let second = session(storage)
        await second.load()

        #expect(second.feed().count == 1)
        #expect(second.feed().first?.commentCount == 1)
    }

    // MARK: Epic 6 — invite and join

    @Test("A new room has one member: you")
    func roomStartsWithOneMember() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        await app.load()
        try await app.createIdentity(displayName: "Cassilda")
        let room = try await app.createRoom(named: "Hangar 7")

        #expect(app.rooms.first?.memberCount == 1)
        #expect(app.roster(of: room).founder == app.enrolment?.identity.id)
    }

    @Test("Attesting a joiner offers a new room and admits nobody")
    func attestingDoesNotAdmit() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        await app.load()
        try await app.createIdentity(displayName: "Cassilda")
        let room = try await app.createRoom(named: "Hangar 7")

        let hastur = Identity.generate()
        let attestation = try await app.attest(code: JoinerCode(keys: hastur.publicKeys, commitment: JoinCommitment.of(TestInvite.nonce(for: hastur.publicKeys))), joining: room)

        #expect(attestation.joiner == hastur.id)
        #expect(app.roster(of: room).requests[hastur.id] == attestation)
        #expect(app.rooms.first?.memberCount == 1, "an invitation put somebody in the room")
        #expect(app.roster(of: room).invited.contains(hastur.id))
        #expect(app.pendingJoins(in: room).isEmpty)
    }

    @Test("Admitting a joiner records the room's half and waits for theirs")
    func admitting() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        await app.load()
        try await app.createIdentity(displayName: "Cassilda")
        let room = try await app.createRoom(named: "Hangar 7")

        try await app.setAccess(.anyMember, in: room)

        let hastur = Identity.generate()
        let attestation = try await app.attest(code: JoinerCode(keys: hastur.publicKeys, commitment: JoinCommitment.of(TestInvite.nonce(for: hastur.publicKeys))), joining: room)

        #expect(app.pendingJoins(in: room).count == 1)
        try await app.decide(on: attestation, admit: true)

        #expect(app.pendingJoins(in: room).isEmpty)
        #expect(app.roster(of: room).admissions[hastur.id]?.count == 1)
        #expect(
            app.roster(of: room).members.count == 1,
            "an approval alone admitted somebody who has confirmed nothing")
    }

    @Test("Refusing keeps them out and stays on the record")
    func refusing() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        await app.load()
        try await app.createIdentity(displayName: "Cassilda")
        let room = try await app.createRoom(named: "Hangar 7")

        try await app.setAccess(.anyMember, in: room)

        let hastur = Identity.generate()
        let attestation = try await app.attest(code: JoinerCode(keys: hastur.publicKeys, commitment: JoinCommitment.of(TestInvite.nonce(for: hastur.publicKeys))), joining: room)
        try await app.decide(on: attestation, admit: false)

        #expect(app.rooms.first?.memberCount == 1)
        #expect(app.roster(of: room).refusals[hastur.id]?.count == 1)
        #expect(app.pendingJoins(in: room).isEmpty)
    }

    @Test("An attestation from a stranger cannot be admitted")
    func strangerAttestationRefused() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        await app.load()
        try await app.createIdentity(displayName: "Cassilda")
        let room = try await app.createRoom(named: "Hangar 7")

        let stranger = Identity.generate()
        let joiner = Identity.generate()
        let forged = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: stranger, at: start)

        await #expect(throws: MembershipError.inviterNotAMember) {
            try await app.decide(on: forged, admit: true)
        }
        #expect(app.rooms.first?.memberCount == 1)
    }

    @Test("An invitation and the room's answer survive a relaunch")
    func membershipPersists() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = session(storage)
        await first.load()
        try await first.createIdentity(displayName: "Cassilda")
        let room = try await first.createRoom(named: "Hangar 7")
        let hastur = Identity.generate()
        try await first.decide(
            on: try await first.attest(code: JoinerCode(keys: hastur.publicKeys, commitment: JoinCommitment.of(TestInvite.nonce(for: hastur.publicKeys))), joining: room), admit: true)

        let second = session(storage)
        await second.load()

        #expect(second.roster(of: room).admissions[hastur.id]?.count == 1)
        #expect(second.roster(of: room).requests[hastur.id] != nil, "the invitation was forgotten")
    }

    @Test("Room organisation survives a relaunch too")
    func organisationPersists() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = session(storage)
        await first.load()
        try await first.createIdentity(displayName: "Cassilda")
        let room = try await first.createRoom(named: "Zeppelin Enthusiasts")

        let stamp = first.stamp()
        first.updateOrganisation { $0.setPinned(true, for: room, stamp: stamp) }
        try await Task.sleep(for: .milliseconds(50))

        let second = session(storage)
        await second.load()

        #expect(second.organisation.isPinned(room))
    }

    @Test("Nothing readable reaches the disk")
    func logOnDiskIsCiphertext() async throws {
        let (storage, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = session(storage)
        await app.load()
        try await app.createIdentity(displayName: "Cassilda")
        let room = try await app.createRoom(named: "Zeppelin Enthusiasts")
        try await app.send("the mooring mast drawings are 1:200", to: room)

        let onDisk = try Data(contentsOf: directory.appending(path: "log.carpenter"))

        for fragment in ["mooring", "Cassilda", "Zeppelin"] {
            let leaked = onDisk.contains(Data(fragment.utf8))
            #expect(!leaked, "\(fragment) reached the disk in plaintext")
        }
    }
}

@Suite("Persisted state tolerates fields it has never seen")
struct PersistedStateCompatibilityTests {
    @Test("A state file written before a field existed still decodes")
    func missingFieldsFallBackToDefaults() throws {
        let old = Data(#"{"knownRooms":[]}"#.utf8)

        let restored = try JSONDecoder().decode(PersistedState.self, from: old)

        #expect(restored.knownRooms.isEmpty)
        #expect(restored.knownKeys.isEmpty)
        #expect(restored.epochs.isEmpty)
        #expect(restored.syncedFrontier.isEmpty)
    }

    @Test("An empty object decodes rather than throwing")
    func emptyObject() throws {
        #expect(throws: Never.self) {
            try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        }
    }

    @Test("What it writes, it reads back whole")
    func roundTrip() throws {
        var state = PersistedState()
        state.knownRooms = [RoomID()]
        state.knownKeys = [Identity.generate().publicKeys]
        state.epochs = [state.knownRooms[0]: [0, 1]]

        let restored = try JSONDecoder().decode(
            PersistedState.self, from: try JSONEncoder().encode(state))

        #expect(restored.knownRooms == state.knownRooms)
        #expect(restored.knownKeys == state.knownKeys)
        #expect(restored.epochs == state.epochs)
    }
}

@Suite("Integrity is reported, never repaired", .serialized)
@MainActor
struct IntegrityReportingTests {
    private func scratch() -> URL {
        URL.temporaryDirectory.appending(path: "carpenter-integrity-\(UUID().uuidString)")
    }

    private func session(at directory: URL, keychain: InMemoryKeychainStore) -> AppSession {
        AppSession(
            storage: SessionStorage(
                keychain: keychain,
                log: FileLogStore(url: directory.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json"))
            ),
            clock: TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        )
    }

    @Test("A healthy device says so")
    func cleanReport() async throws {
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let alice = session(at: directory, keychain: InMemoryKeychainStore())
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        try await alice.createRoom(named: "Hangar 7")

        #expect(alice.integrity.isClean)
        #expect(!alice.integrity.hasDiverged)
    }

    @Test("A torn tail is reported rather than silently swallowed")
    func tornTailSurfaces() async throws {
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keychain = InMemoryKeychainStore()
        let log = directory.appending(path: "log.carpenter")

        let alice = session(at: directory, keychain: keychain)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        try await alice.createRoom(named: "Hangar 7")
        try await alice.send("something", to: alice.rooms[0].id)

        let bytes = try Data(contentsOf: log)
        try bytes.prefix(bytes.count - 40).write(to: log)

        let reopened = session(at: directory, keychain: keychain)
        await reopened.load()

        #expect(!reopened.integrity.isClean)
        #expect(reopened.integrity.lastLoad == .tornTail)
        #expect(reopened.integrity.discardedBytes > 0)
    }

    @Test("An entry that no longer verifies is counted, not quietly dropped")
    func unverifiableEntriesAreCounted() async throws {
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let keychain = InMemoryKeychainStore()
        let log = directory.appending(path: "log.carpenter")

        let alice = session(at: directory, keychain: keychain)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("the original", to: room)

        var bytes = try Data(contentsOf: log)
        let marker = Data("\"signature\":\"".utf8)
        let found = try #require(bytes.range(of: marker))
        let victim = found.upperBound
        bytes[victim] = bytes[victim] == UInt8(ascii: "A") ? UInt8(ascii: "B") : UInt8(ascii: "A")
        try bytes.write(to: log)

        let reopened = session(at: directory, keychain: keychain)
        await reopened.load()

        #expect(reopened.integrity.unverifiableOnDisk > 0)
        #expect(!reopened.integrity.isClean)
        #expect(reopened.integrity.lastLoad == .complete)
    }

    @Test("A fork makes the report say the device has diverged")
    func forksAreReported() throws {
        let alice = Author()
        var replica = Replica()
        try replica.meet(alice)

        let chain = alice.chain
        func entry(_ text: String) throws -> Entry {
            try Entry.append(
                to: nil, author: alice.identity.id, device: alice.device, clock: VectorClock(),
                wallTime: Date(timeIntervalSince1970: 1), room: nil,
                payload: try Payload.post(text).sealed(at: .initial, using: chain))
        }

        _ = try replica.integrate(try entry("one version"))
        _ = try replica.integrate(try entry("another version"))

        var report = IntegrityReport()
        report.forks = replica.forks

        #expect(report.hasDiverged)
        #expect(!report.isClean)
        #expect(replica.allEntries.count == 2)
    }
}

@Suite("Devices and pairing", .serialized)
@MainActor
struct DeviceListTests {
    private func scratch() -> URL {
        URL.temporaryDirectory.appending(path: "carpenter-devices-\(UUID().uuidString)")
    }

    private func session() throws -> AppSession {
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(),
                log: FileLogStore(url: directory.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json"))
            ),
            clock: TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        )
    }

    @Test("A new identity lists exactly the device it was made on")
    func oneDeviceToStart() async throws {
        let alice = try session()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")

        #expect(alice.devices.count == 1)
        #expect(alice.devices[0].isCurrent)
        #expect(alice.devices[0].isActive)
    }

    @Test("A device cannot revoke itself")
    func cannotRevokeSelf() async throws {
        let alice = try session()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")

        let current = try #require(alice.devices.first { $0.isCurrent })
        await #expect(throws: AppSessionError.cannotRevokeThisDevice) {
            try await alice.revoke(current.id)
        }
        #expect(alice.devices.first { $0.isCurrent }?.isActive == true)
    }

}

extension DeviceListTests {
    @Test("The founding device says when it was made")
    func foundingDeviceSaysWhenItWasMade() async throws {
        let alice = try session()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")

        let current = try #require(alice.devices.first { $0.isCurrent })
        #expect(
            current.addedAt != nil,
            """
            This used to assert the opposite. Every device self-certified at .distantPast, which \
            the screen drew as "here since you made this identity" — true of the founding device \
            and claimed by every later one. Changed 2026-09-13; see `TheDeviceListTellsTheTruthTests`.
            """)
    }

}

@Suite("A second device on one account", .serialized)
@MainActor
struct SecondDeviceTests {
    private func storage(_ keychain: InMemoryKeychainStore) -> SessionStorage {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-2nd-\(UUID().uuidString)")
        return SessionStorage(
            keychain: keychain,
            log: FileLogStore(url: directory.appending(path: "log.carpenter")),
            documents: FileDocumentStore(url: directory.appending(path: "state.json"))
        )
    }

    @Test("You cannot invite yourself into a room")
    func cannotInviteYourself() async throws {
        let session = AppSession(storage: storage(InMemoryKeychainStore()), clock: TestClock(now: .now))
        await session.load()
        try await session.createIdentity(displayName: "Alice")
        let room = try await session.createRoom(named: "Kitchen")

        await #expect(throws: AppSessionError.thatIsYou) {
            _ = try await session.invite(
                joinerCode: session.identityCode(), joining: room, mailbox: nil)
        }
    }

    @Test("Rechecking does nothing to a session that already has an identity")
    func recheckLeavesAReadySessionAlone() async throws {
        let session = AppSession(storage: storage(InMemoryKeychainStore()), clock: TestClock(now: .now))
        await session.load()
        try await session.createIdentity(displayName: "Griff")

        #expect(await session.recheckForSyncedIdentity() == false)
        #expect(session.state == .ready)
    }
}

@Suite("A device that has never spoken says so", .serialized)
@MainActor
struct UnusedDeviceTests {
    private func session() -> AppSession { TestSession.make() }

}

