import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Sync from the app", .serialized)
@MainActor
struct SyncFromTheAppTests {
    private func scratch() -> URL {
        URL.temporaryDirectory.appending(path: "carpenter-sync-\(UUID().uuidString)")
    }

    private func session(_ clock: TestClock) throws -> AppSession {
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(),
                log: FileLogStore(url: directory.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json"))
            ),
            clock: clock
        )
    }

    @Test("A joiner syncs, is admitted, and reads history from before they arrived")
    func joinerConverges() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let mailbox = InMemoryMailbox()

        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("door code changed again", to: room)

        let bobKeys = try #require(bob.enrolment?.identity.publicKeys)
        let attestation = try await alice.attest(code: try JoinerCode.decoded(from: bob.identityCode()), joining: room)
        #expect(alice.roster(of: room).members.count == 1, "an invitation put somebody in the room")
        #expect(alice.roster(of: room).invited.contains(bobKeys.participantID))

        try await alice.sync(through: mailbox)

        try await bob.accept(attestation, from: try #require(alice.enrolment?.identity.publicKeys))

        var received = SyncReport()
        for _ in 0..<3 {
            try await alice.sync(through: mailbox)
            let round = try await bob.sync(through: mailbox)
            if round.grantsReceived.count > 0 { received = round }
        }

        #expect(alice.roster(of: room).members.count == 2, "confirming did not let Bob in")
        #expect(received.grantsReceived.count == 1)
        #expect(received.entriesReceived > 0)

        let seen = bob.messages(in: room).map { $0.body }
        #expect(seen.contains("door code changed again"))
    }

    @Test("Two sessions converge through a mailbox on disk")
    func convergesOverFileMailbox() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let mailbox = FileMailbox(directory: directory)

        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("before you arrived", to: room)

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())

        var received = SyncReport()
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            let round = try await bob.sync(through: mailbox)
            if round.grantsReceived.count > 0 { received = round }
        }

        #expect(received.grantsReceived.count == 1)
        #expect(bob.messages(in: room).map(\.body).contains("before you arrived"))

        try await bob.send("made it", to: room)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        #expect(alice.messages(in: room).map(\.body).contains("made it"))
    }

    @Test("An open room hands the joiner a key without the inviter admitting them")
    func openRoomGrantsAtBaseEpoch() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let mailbox = InMemoryMailbox()

        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("before you arrived", to: room)

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())

        #expect(alice.epoch(of: room) == .initial, "an invitation turned the key on its own")
        #expect(alice.roster(of: room).members.count == 1, "the invitation alone admitted somebody")

        var received = SyncReport()
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            let round = try await bob.sync(through: mailbox)
            if round.grantsReceived.count > 0 { received = round }
        }

        #expect(
            alice.epoch(of: room) == EpochNumber.initial.next,
            "a membership change did not turn the key")
        #expect(alice.roster(of: room).members.count == 2, "confirming did not admit")

        #expect(received.grantsReceived.count == 1)
        #expect(bob.rooms.map(\.name).contains("Hangar 7"))
        #expect(bob.messages(in: room).map(\.body).contains("before you arrived"))

        #expect(bob.feed().isEmpty, "an unreadable Wall entry leaked into the feed")

        let idle = try await alice.sync(through: mailbox)
        #expect(idle.packetsWritten == 0, "an idle sync rewrote a packet and would push again")
    }

    @Test("A read-only refresh writes nothing, even with a key owed")
    func fetchOnlyRefreshWritesNothing() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let mailbox = InMemoryMailbox()

        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("before you arrived", to: room)
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())

        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        try await bob.send("I am here", to: room)
        try await bob.sync(through: mailbox)

        let before = await mailbox.serverWrites
        let readOnly = try await alice.sync(through: mailbox, mode: .readOnly)
        let after = await mailbox.serverWrites

        #expect(readOnly.entriesReceived > 0, "precondition: the refresh had something to read")
        #expect(
            after == before,
            "a read-only refresh wrote to the server \(after - before) time(s)")
        #expect(readOnly.packetsWritten == 0)
        #expect(readOnly.bellsRung == 0, "a read-only refresh rang somebody's bell")
    }

    @Test("A read-only refresh leaves an owed key owed")
    func readOnlyRefreshKeepsTheObligation() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let mailbox = InMemoryMailbox()

        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("before you arrived", to: room)
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        #expect(alice.roster(of: room).members.count == 2, "precondition: Bob is in the room")

        let readOnly = try await alice.sync(through: mailbox, mode: .readOnly)
        #expect(readOnly.packetsWritten == 0)

        let nothingYet = try await bob.sync(through: mailbox)
        #expect(nothingYet.grantsReceived.isEmpty, "a read-only refresh put a grant in the mailbox")

        try await alice.sync(through: mailbox)
        let afterward = try await bob.sync(through: mailbox)
        #expect(afterward.grantsReceived.count == 1)
    }

    @Test("A joiner who relaunches before syncing still knows who invited them")
    func joinerSurvivesRelaunchBeforeFirstSync() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let mailbox = FileMailbox(directory: directory)

        let alice = try session(clock)
        let bobDirectory = scratch()
        try FileManager.default.createDirectory(at: bobDirectory, withIntermediateDirectories: true)
        let bobKeychain = InMemoryKeychainStore()
        func bobSession() -> AppSession {
            AppSession(
                storage: SessionStorage(
                    keychain: bobKeychain,
                    log: FileLogStore(url: bobDirectory.appending(path: "log.carpenter")),
                    documents: FileDocumentStore(url: bobDirectory.appending(path: "state.json"))
                ),
                clock: clock)
        }

        let bob = bobSession()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("before you arrived", to: room)

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        let relaunched = bobSession()
        await relaunched.load()
        var received = SyncReport()
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            let round = try await relaunched.sync(through: mailbox)
            if round.entriesReceived > 0 { received = round }
        }

        #expect(received.entriesReceived > 0)
        #expect(relaunched.messages(in: room).map(\.body).contains("before you arrived"))
    }

    @Test("What arrives in a sync is still there after a relaunch")
    func receivedEntriesReachTheDisk() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let mailbox = FileMailbox(directory: directory)

        let alice = try session(clock)
        let bobDirectory = scratch()
        try FileManager.default.createDirectory(at: bobDirectory, withIntermediateDirectories: true)
        let bobKeychain = InMemoryKeychainStore()
        func bobSession() -> AppSession {
            AppSession(
                storage: SessionStorage(
                    keychain: bobKeychain,
                    log: FileLogStore(url: bobDirectory.appending(path: "log.carpenter")),
                    documents: FileDocumentStore(url: bobDirectory.appending(path: "state.json"))
                ),
                clock: clock)
        }

        let bob = bobSession()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("before you arrived", to: room)
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(bob.messages(in: room).map(\.body).contains("before you arrived"))

        let relaunched = bobSession()
        await relaunched.load()

        #expect(relaunched.rooms.contains { $0.id == room })
        #expect(relaunched.messages(in: room).map(\.body).contains("before you arrived"))
    }

    @Test("Sharing a room is what gives you somebody's name")
    func roomMatesLearnNames() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let mailbox = FileMailbox(directory: directory)

        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let aliceID = try #require(alice.enrolment?.identity.id)
        let room = try await alice.createRoom(named: "Hangar 7")

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(bob.member(aliceID).displayName == "Alice")
    }

    @Test("A stranger stays an identifier, not an invented name")
    func strangersHaveNoName() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let alice = try session(clock)
        let stranger = try session(clock)
        await alice.load()
        await stranger.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await stranger.createIdentity(displayName: "Nobody")
        await stranger.optIntoNames()

        let strangerID = try #require(stranger.enrolment?.identity.id)

        #expect(alice.member(strangerID).displayName != "Nobody")
    }

    @Test("Renaming yourself renames you in every room")
    func renameReachesEveryRoom() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let alice = try session(clock)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()

        let aliceID = try #require(alice.enrolment?.identity.id)
        let first = try await alice.createRoom(named: "Hangar 7")
        let second = try await alice.createRoom(named: "Allotment")

        try await alice.setDisplayName("Alexandra")

        #expect(alice.announcedName(of: aliceID, in: first) == "Alexandra")
        #expect(alice.announcedName(of: aliceID, in: second) == "Alexandra")
        #expect(alice.member(aliceID).displayName == "Alexandra")
    }

    @Test("An unchanged name is not announced twice")
    func announcingIsIdempotent() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let alice = try session(clock)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()

        _ = try await alice.createRoom(named: "Hangar 7")

        let before = alice.entryCount

        try await alice.setDisplayName("Alice")
        try await alice.setDisplayName("Alice")

        #expect(alice.entryCount == before)
    }

    @Test("A second sync sends only what is new")
    func syncSendsTheDifference() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let mailbox = InMemoryMailbox()

        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        let bobKeys = try #require(bob.enrolment?.identity.publicKeys)
        let attestation = try await alice.attest(code: try JoinerCode.decoded(from: bob.identityCode()), joining: room)
        try await alice.decide(on: attestation, admit: true)

        let first = try await alice.sync(through: mailbox)
        #expect(first.entriesSent > 0)

        try await alice.send("one more", to: room)
        let second = try await alice.sync(through: mailbox)

        #expect(second.entriesSent == 1)
    }

    @Test("Nothing to say and nobody to say it to writes no packet")
    func idleSyncIsFree() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let mailbox = InMemoryMailbox()

        let alice = try session(clock)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await alice.createRoom(named: "Alone")

        let report = try await alice.sync(through: mailbox)
        #expect(report.packetsWritten == 0)
        #expect(!report.didAnything)
    }

    @Test("Joining an open room turns the key, with nothing called by hand")
    func openInvitationAdvancesTheEpoch() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let mailbox = InMemoryMailbox()
        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        #expect(alice.roster(of: room).access == .open, "the default room is not open any more")
        #expect(alice.epoch(of: room) == .initial)

        try await join(bob, into: room, of: alice, through: mailbox)

        #expect(
            alice.epoch(of: room) == EpochNumber.initial.next,
            "a membership change left the key where it was")
    }

    @Test("One join turns the key once, even if the inviter also decides")
    func oneJoinAdvancesOnce() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let mailbox = InMemoryMailbox()
        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: room, of: alice, through: mailbox)
        #expect(alice.epoch(of: room) == EpochNumber.initial.next)

        let attestation = try #require(alice.roster(of: room).requests.values.first)
        try await alice.decide(on: attestation, admit: true)
        #expect(
            alice.epoch(of: room) == EpochNumber.initial.next,
            "one membership change turned the key twice")
    }

    @Test("An approval before a confirmation still turns the key once")
    func approvalFirstAdvancesOnce() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let mailbox = InMemoryMailbox()
        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7", access: .founder)
        let bobKeys = try #require(bob.enrolment?.identity.publicKeys)
        let attestation = try await alice.attest(code: try JoinerCode.decoded(from: bob.identityCode()), joining: room)

        try await alice.decide(on: attestation, admit: true)
        let afterAdmission = try #require(alice.epoch(of: room))
        #expect(afterAdmission == EpochNumber.initial.next)
        #expect(!alice.roster(of: room).members.contains(bobKeys.participantID), "approval admitted")

        try await bob.accept(attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        #expect(alice.roster(of: room).members.contains(bobKeys.participantID))
        #expect(
            alice.epoch(of: room) == afterAdmission,
            "one join turned the key twice because the approval arrived first")
    }

    @Test("Admitting somebody advances the room's epoch")
    func admissionAdvancesTheEpoch() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7", access: .founder)
        #expect(alice.epoch(of: room) == EpochNumber.initial)

        let bobKeys = try #require(bob.enrolment?.identity.publicKeys)
        let attestation = try await alice.attest(code: try JoinerCode.decoded(from: bob.identityCode()), joining: room)
        try await alice.decide(on: attestation, admit: true)

        #expect(alice.epoch(of: room) == EpochNumber.initial.next)

        try await alice.send("after the join", to: room)
        #expect(alice.messages(in: room).contains { $0.body == "after the join" })
    }

    @Test("A member who refused hands out no key")
    func refusalWithholdsTheKey() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_786_635_000))
        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        let bobKeys = try #require(bob.enrolment?.identity.publicKeys)
        let attestation = try await alice.attest(code: try JoinerCode.decoded(from: bob.identityCode()), joining: room)
        try await alice.decide(on: attestation, admit: false)

        let roster = alice.roster(of: room)
        #expect(roster.whoRefused(bobKeys.participantID).count == 1)
        #expect(!roster.rewrapTargets(of: try #require(alice.enrolment?.identity.id))
            .contains(bobKeys.participantID))
    }
}
