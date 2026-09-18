import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Hiding a message", .serialized)
@MainActor
struct SoftDeleteTests {
    private func scratch() -> URL {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-hide-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func session(
        at directory: URL, keychain: InMemoryKeychainStore = InMemoryKeychainStore()
    ) -> AppSession {
        AppSession(
            storage: SessionStorage(
                keychain: keychain,
                log: FileLogStore(url: directory.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json"))
            ),
            clock: TestClock(now: TestSession.now)
        )
    }

    @Test("A hidden message stops being drawn, and comes back")
    func hideAndReveal() async throws {
        let alice = session(at: scratch())
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let room = try await alice.createRoom(named: "Hangar 7")

        try await alice.send("keep this", to: room)
        try await alice.send("hide this", to: room)

        let target = try #require(alice.messages(in: room).first { $0.body == "hide this" })
        await alice.hide(target.id)

        #expect(!alice.messages(in: room).contains { $0.body == "hide this" })
        #expect(alice.messages(in: room).contains { $0.body == "keep this" })
        #expect(alice.hiddenMessageCount == 1)

        await alice.reveal(target.id)
        #expect(alice.messages(in: room).contains { $0.body == "hide this" })
        #expect(alice.hiddenMessageCount == 0)
    }

    @Test("Hiding survives a relaunch, and so does the way back")
    func survivesRelaunch() async throws {
        let directory = scratch()
        let keychain = InMemoryKeychainStore()
        let first = session(at: directory, keychain: keychain)
        await first.load()
        try await first.createIdentity(displayName: "Alice")
        let room = try await first.createRoom(named: "Hangar 7")
        try await first.send("hide this", to: room)

        let target = try #require(first.messages(in: room).first)
        await first.hide(target.id)

        let second = session(at: directory, keychain: keychain)
        await second.load()
        #expect(second.messages(in: room).isEmpty, "the hidden message came back on relaunch")
        #expect(second.hiddenMessageCount == 1)

        await second.revealAllHidden()
        #expect(second.messages(in: room).contains { $0.body == "hide this" })
    }

    @Test("Hiding a message does not withhold it from peers")
    func hiddenEntriesStillSync() async throws {
        let mailbox = InMemoryMailbox()
        let alice = session(at: scratch())
        let bob = session(at: scratch())
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        try await alice.send("everyone keeps this", to: room)

        let target = try #require(alice.messages(in: room).first { $0.body == "everyone keeps this" })
        await alice.hide(target.id)
        #expect(!alice.messages(in: room).contains { $0.body == "everyone keeps this" })

        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        #expect(
            bob.messages(in: room).contains { $0.body == "everyone keeps this" },
            "hiding on one device removed the message from somebody else's history")
    }
}

@Suite("Hiding across a member's devices")
struct MemberPreferencesTests {
    private let phone = DeviceID(rawValue: WideID.of([1]))
    private let pad = DeviceID(rawValue: WideID.of([2]))
    private let entry = EntryHash(rawValue: Data([9]))
    private let other = EntryHash(rawValue: Data([8]))
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func stamp(_ device: DeviceID, _ offset: TimeInterval) -> OrganisationStamp {
        OrganisationStamp(at: start.addingTimeInterval(offset), device: device)
    }

    @Test("What one device hides, the other hides")
    func hidingTravels() {
        var onPhone = MemberPreferences()
        onPhone.setHidden(true, for: entry, stamp: stamp(phone, 0))

        let onPad = MemberPreferences().merged(with: onPhone)
        #expect(onPad.isHidden(entry))
    }

    @Test("Putting a message back beats an earlier hide")
    func revealBeatsAnEarlierHide() {
        var onPhone = MemberPreferences()
        onPhone.setHidden(true, for: entry, stamp: stamp(phone, 0))

        var onPad = MemberPreferences().merged(with: onPhone)
        onPad.reveal([entry], stamp: stamp(pad, 60))

        #expect(!onPhone.merged(with: onPad).isHidden(entry), "the message stayed hidden forever")
        #expect(!onPad.merged(with: onPhone).isHidden(entry), "the merge is not order-independent")
    }

    @Test("A later hide beats an earlier reveal")
    func hideBeatsAnEarlierReveal() {
        var onPad = MemberPreferences()
        onPad.setHidden(false, for: entry, stamp: stamp(pad, 0))

        var onPhone = MemberPreferences()
        onPhone.setHidden(true, for: entry, stamp: stamp(phone, 60))

        #expect(onPad.merged(with: onPhone).isHidden(entry))
        #expect(onPhone.merged(with: onPad).isHidden(entry))
    }

    @Test("Two devices hiding different messages keep both")
    func independentHidesBothSurvive() {
        var onPhone = MemberPreferences()
        onPhone.setHidden(true, for: entry, stamp: stamp(phone, 0))

        var onPad = MemberPreferences()
        onPad.setHidden(true, for: other, stamp: stamp(pad, 0))

        let merged = onPhone.merged(with: onPad)
        #expect(merged.isHidden(entry))
        #expect(merged.isHidden(other))
    }

    @Test("Putting a message back leaves a dated fact, not an absence")
    func revealIsRecordedNotErased() {
        var prefs = MemberPreferences()
        prefs.setHidden(true, for: entry, stamp: stamp(phone, 0))
        prefs.reveal([entry], stamp: stamp(phone, 60))

        #expect(prefs.hidden[entry] != nil, "the flag was erased and has nothing to merge with")
        #expect(!prefs.isHidden(entry))
    }

    @Test("A feed written before preferences existed still decodes")
    func olderFeedDecodes() throws {
        let json = Data(#"{"entries":[],"certificates":[]}"#.utf8)
        let feed = try JSONDecoder().decode(SiblingFeed.self, from: json)
        #expect(feed.preferences.hiddenEntries.isEmpty)
    }
}

@MainActor
@Suite("A transcript that is short says why", .serialized)
struct HiddenCountTests {
    @Test("A room names how many of its own messages this member hid")
    func theRoomNamesItsOwnHidden() async throws {
        let session = TestSession.make()
        await session.load()
        try await session.createIdentity(displayName: "Alice")
        let room = try await session.createRoom(named: "Lanterns")
        let other = try await session.createRoom(named: "Somewhere else")

        try await session.send("first", to: room)
        try await session.send("second", to: room)
        try await session.send("elsewhere", to: other)

        let target = try #require(session.messages(in: room).first { $0.body == "first" })
        await session.hide(target.id)

        #expect(
            session.hiddenMessageCount(in: room) == 1,
            """
            A transcript that is quietly short reads as something having failed to load. The room \
            has to be able to say the number, or the omission is indistinguishable from a fault.
            """)
        #expect(
            session.hiddenMessageCount(in: other) == 0,
            "a message hidden in one room was counted against another")
        #expect(session.hiddenMessageCount == 1, "the count across every room disagreed")
    }

    @Test("Showing them again takes the count back to nothing")
    func revealingClearsTheCount() async throws {
        let session = TestSession.make()
        await session.load()
        try await session.createIdentity(displayName: "Alice")
        let room = try await session.createRoom(named: "Lanterns")
        try await session.send("first", to: room)
        try await session.send("second", to: room)

        for message in session.messages(in: room) { await session.hide(message.id) }
        #expect(session.hiddenMessageCount(in: room) == 2)

        await session.revealHidden(in: room)
        #expect(
            session.hiddenMessageCount(in: room) == 0,
            "the room still says messages are hidden after they were all shown again")
    }
}
