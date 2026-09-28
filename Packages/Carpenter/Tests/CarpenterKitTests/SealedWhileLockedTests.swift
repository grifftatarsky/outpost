@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Synchronization
import Testing

@MainActor
@Suite("With Advanced On Device Security on, what this phone keeps is sealed while it is locked", .serialized)
struct SealedWhileLockedTests {
    @MainActor
    private struct Rig {
        let alice: AppSession
        let bob: AppSession
        let keychain: InMemoryKeychainStore
        let dial: ProtectionDial
        let directory: URL
        let mailbox: InMemoryMailbox
        let room: RoomID
        let clock: TestClock

        func lock() async {
            await keychain.lockPhone()
            bob.phoneLocked(true)
        }

        func unlock() async {
            await keychain.unlockPhone()
            bob.phoneLocked(false)
        }

        func round(_ count: Int = 1) async throws {
            for _ in 0..<count {
                try await alice.sync(through: mailbox)
                try await bob.sync(through: mailbox)
            }
        }

        func bobHas(_ words: String) -> Bool { bob.messages(in: room).contains { $0.body == words } }

        func bobRelaunched() -> AppSession {
            dial.turn(to: .afterFirstUnlock)
            return TestSession.make(keychain: keychain, at: directory, protection: dial, clock: clock)
        }
    }

    private func rig(sealed: Bool = true, log wrap: (any LogStore) -> any LogStore = { $0 }) async throws -> Rig {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let dial = ProtectionDial()
        let keychain = InMemoryKeychainStore(protection: dial)
        let directory = TestScratch.root.appending(path: "carpenter-sealed-\(UUID().uuidString)")
        let stored = TestSession.storage(keychain: keychain, at: directory, protection: dial)
        let alice = TestSession.make(clock: clock)
        let bob = AppSession(
            storage: SessionStorage(
                keychain: keychain, log: wrap(stored.log), documents: stored.documents, media: stored.media,
                protection: dial),
            clock: clock, denyList: .empty)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Vault")
        try await join(bob, into: room, of: alice, through: mailbox)
        if sealed { try await bob.sealWhileLocked(true) }
        return Rig(
            alice: alice, bob: bob, keychain: keychain, dial: dial, directory: directory, mailbox: mailbox, room: room,
            clock: clock)
    }

    // MARK: Nothing is read or written while the phone is locked

    @Test("A round while the phone is locked collects nothing and signs for nothing, and the message arrives on unlock")
    func aLockedPhoneCollectsNothing() async throws {
        let t = try await rig()
        await t.lock()
        try await t.alice.send("while you were away", to: t.room)
        try await t.alice.sync(through: t.mailbox)
        let (fetches, receipts) = (await t.mailbox.fetchCount, await t.mailbox.acknowledgeCount)

        for _ in 0..<3 { _ = try await t.bob.sync(through: t.mailbox) }
        #expect(await t.mailbox.fetchCount == fetches, "a sealed phone fetched from iCloud")
        #expect(await t.mailbox.acknowledgeCount == receipts, "a sealed phone signed for what it could not write down")
        #expect(!t.bobHas("while you were away"))

        await t.unlock()
        try await t.round(3)
        #expect(t.bobHas("while you were away"), "a message sent while the phone was locked never arrived")
    }

    @Test("A phone that starts while locked waits for it to unlock, and never offers to start over")
    func aLockedStartWaits() async throws {
        let t = try await rig()
        try await t.alice.send("before the lock", to: t.room)
        try await t.round(3)
        try #require(t.bobHas("before the lock"), "precondition: Bob has the message")

        await t.keychain.lockPhone()
        let later = t.bobRelaunched()
        later.phoneLocked(true)
        await later.readProtection()
        await later.load()
        #expect(later.waitsForUnlock)
        #expect(later.state == .loading, "a locked phone was shown \(later.state) instead of waiting")
        #expect(later.enrolment == nil, "the member's keys were opened while the phone was locked")

        await t.keychain.unlockPhone()
        later.phoneLocked(false)
        await later.readProtection()
        await later.load()
        #expect(later.state == .ready, "unlocking did not open the app")
        #expect(later.messages(in: t.room).contains { $0.body == "before the lock" }, "history did not come back on unlock")
    }

    @Test("An extension woken while the phone is locked can read nothing, so its banner can only say that something arrived")
    func theExtensionReadsNothing() async throws {
        let t = try await rig()
        await t.lock()
        try await t.alice.send("not for the lock screen", to: t.room)
        try await t.alice.sync(through: t.mailbox)

        let nse = AppSession(
            storage: TestSession.storage(keychain: t.keychain, at: t.directory).readOnly, clock: t.clock,
            denyList: .empty)
        await nse.load()
        #expect(nse.enrolment == nil, "the extension opened the member's keys while the phone was locked")
        #expect(nse.latestIncomingMessage() == nil)
    }

    @Test("With it off, the extension still reads while the phone is locked, as it always has")
    func offLeavesTheExtensionReading() async throws {
        let t = try await rig(sealed: false)
        await t.lock()
        let nse = AppSession(
            storage: TestSession.storage(keychain: t.keychain, at: t.directory).readOnly, clock: t.clock,
            denyList: .empty)
        await nse.load()
        #expect(nse.enrolment != nil, "turning nothing on still sealed the keys from the extension")
    }

    @Test("A write refused because the phone locked mid-round is not reported as damage, and is written after unlock")
    func aLockMidRoundIsNotDamage() async throws {
        let refusing = LocksOnFirstWrite()
        let t = try await rig(log: { refusing.wrapping($0) })
        try await t.alice.send("sent as the phone locked", to: t.room)
        try await t.alice.sync(through: t.mailbox)
        let receipts = await t.mailbox.acknowledgeCount
        await refusing.arm { await t.lock() }

        _ = try? await t.bob.sync(through: t.mailbox)
        #expect(t.bob.integrity.writesFailed == 0, "a write the lock refused was counted as damage")
        #expect(await t.mailbox.acknowledgeCount == receipts, "a packet was signed for before it was written down")

        await t.unlock()
        try await t.round(3)
        let later = t.bobRelaunched()
        await later.readProtection()
        await later.load()
        #expect(
            later.messages(in: t.room).contains { $0.body == "sent as the phone locked" },
            "what the refused write held never reached the disk")
    }

    // MARK: The setting, the keys and the record agree

    @Test("Turning it on seals every key this phone already kept, and turning it off opens them again")
    func keysFollowTheSetting() async throws {
        let t = try await rig(sealed: false)
        let before = await t.keychain.protectedKeys
        try #require(!before.isEmpty && before.values.allSatisfy { $0 == .afterFirstUnlock })

        try await t.bob.sealWhileLocked(true)
        let on = await t.keychain.protectedKeys
        #expect(Set(on.keys).isSuperset(of: before.keys))
        #expect(on.values.allSatisfy { $0 == .whileUnlocked }, "a key kept before it went on still opens while locked")

        _ = try await t.bob.createRoom(named: "Second vault")
        #expect(
            await t.keychain.protectedKeys.values.allSatisfy { $0 == .whileUnlocked },
            "a key written after it went on opens while locked")

        try await t.bob.sealWhileLocked(false)
        #expect(
            await t.keychain.protectedKeys.values.allSatisfy { $0 == .afterFirstUnlock },
            "turning it off left keys sealed, so notifications could not be drawn")
    }

    @Test("Changes made in quick succession end with the setting, its record and every key agreeing")
    func quickChangesAgree() async throws {
        let t = try await rig(sealed: false)
        let changes = [true, false, true, false, true].map { on in Task { try await t.bob.sealWhileLocked(on) } }
        for change in changes { try await change.value }

        let choice = try #require(t.bob.protectionChoice)
        #expect(choice.isApplied)
        #expect(t.dial.current == choice.chosen, "files are written one way while the setting says another")
        #expect(
            await t.keychain.protectedKeys.values.allSatisfy { $0 == choice.chosen }, "keys disagree with the setting")
        #expect(await ProtectionChoice.read(from: t.keychain) == .read(choice))
    }

    @Test("A setting that cannot be read is never applied as though it were off")
    func unreadableIsNeverAppliedAsOff() async throws {
        let t = try await rig()
        t.dial.turn(to: .afterFirstUnlock)
        let later = TestSession.make(
            keychain: RecordUnreadable(real: t.keychain), at: t.directory, protection: t.dial, clock: t.clock)

        await later.readProtection()
        try? await later.applyProtection()

        #expect(t.dial.current == .whileUnlocked, "a setting nobody could read was taken to be off")
        #expect(
            await t.keychain.protectedKeys.values.allSatisfy { $0 == .whileUnlocked },
            "keys were opened because the setting could not be read")
        #expect(
            await ProtectionChoice.read(from: t.keychain) == .read(ProtectionChoice(chosen: .whileUnlocked, applied: .whileUnlocked)),
            "the setting was rewritten because it could not be read")
    }

    @Test("A setting that cannot be read counts as on, so nothing is written the ordinary way by mistake")
    func unreadableCountsAsOn() async throws {
        #expect(await ProtectionChoice.read(from: UnreadableKeychainStore()) == .unreadable)

        let keychain = InMemoryKeychainStore()
        #expect(await ProtectionChoice.read(from: keychain) == .read(.unset))
        try await keychain.set(Data("not a setting".utf8), for: ProtectionChoice.key, scope: .device)
        #expect(await ProtectionChoice.read(from: keychain) == .unreadable)

        let dial = ProtectionDial()
        let session = TestSession.make(keychain: UnreadableKeychainStore(), protection: dial)
        await session.readProtection()
        #expect(dial.current == .whileUnlocked)
    }

    // MARK: Files

    @Test("Every file the stores keep is written with the protection the setting names at that moment")
    func filesFollowTheSetting() async throws {
        let files = RecordingFileManager()
        let dial = ProtectionDial(.whileUnlocked)
        let folder = TestScratch.root.appending(path: "carpenter-protected-\(UUID().uuidString)", directoryHint: .isDirectory)
        let log = FileLogStore(url: folder.appending(path: "log.carpenter"), protection: dial, fileManager: files)
        let documents = FileDocumentStore(url: folder.appending(path: "state.json"), protection: dial, fileManager: files)
        let media = FileMediaStore(directory: folder.appending(path: "media"), protection: dial, fileManager: files)
        var alice = Author()
        let first = try alice.post("one", at: TestSession.now)
        let second = try alice.post("two", at: TestSession.now.addingTimeInterval(1))

        let writes: [(String, () async throws -> Void)] = [
            ("the log, new", { try await log.append([first, second]) }),
            ("the log, rewritten", { _ = try await log.removeEntries { $0 == first } }),
            ("the state", { try await documents.save(["kept": 1]) }),
            ("a photo", { try await media.store(Data([1, 2, 3]), for: AttachmentID()) }),
        ]
        for (what, write) in writes {
            let before = files.requested.count
            try await write()
            #expect(files.requested.count > before, "\(what) was written without saying how it is protected")
        }
        #expect(files.requested.allSatisfy { $0 == .complete })

        dial.turn(to: .afterFirstUnlock)
        let before = files.requested.count
        try await documents.save(["kept": 2])
        #expect(
            files.requested.dropFirst(before).contains(.completeUntilFirstUserAuthentication),
            "a store kept the protection it was made with")
    }

    @Test("Changing the setting reaches every file and folder already kept, and skips what is not there")
    func reprotectingReachesEverything() throws {
        let files = RecordingFileManager()
        let folder = TestScratch.root.appending(path: "carpenter-kept-\(UUID().uuidString)", directoryHint: .isDirectory)
        let inner = folder.appending(path: "media", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data([1]).write(to: folder.appending(path: "state.json"))
        try Data([2]).write(to: inner.appending(path: "photo.sealed"))

        let refused = ProtectedFiles.reprotect(
            [folder, folder.appending(path: "never-made")], as: .whileUnlocked, using: files)
        #expect(refused.isEmpty)
        #expect(files.requested.count == 4, "a file or folder was left as it was")
        #expect(files.requested.allSatisfy { $0 == .complete })
    }
}

private actor LocksOnFirstWrite {
    private var onWrite: (@Sendable () async -> Void)?

    func arm(_ action: @escaping @Sendable () async -> Void) { onWrite = action }

    nonisolated func wrapping(_ log: any LogStore) -> any LogStore { Refusing(real: log, trigger: self) }

    fileprivate func fire() async -> Bool {
        guard let action = onWrite else { return false }
        onWrite = nil
        await action()
        return true
    }

    private struct Refusing: LogStore {
        let real: any LogStore
        let trigger: LocksOnFirstWrite

        func append(_ entries: [Entry]) async throws {
            if await trigger.fire() { throw CocoaError(.fileWriteNoPermission) }
            try await real.append(entries)
        }

        func loadAll() async throws -> LoadedLog { try await real.loadAll() }

        func removeAll() async throws { try await real.removeAll() }

        func removeEntries(where shouldRemove: @escaping @Sendable (Entry) -> Bool) async throws -> Int {
            try await real.removeEntries(where: shouldRemove)
        }
    }
}

private struct RecordUnreadable: KeychainStore {
    struct Refused: Error {}

    let real: InMemoryKeychainStore

    func data(for key: KeychainKey) async throws -> Data? {
        guard key != ProtectionChoice.key else { throw Refused() }
        return try await real.data(for: key)
    }

    func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) async throws {
        try await real.set(data, for: key, scope: scope)
    }

    func remove(_ key: KeychainKey) async throws { try await real.remove(key) }

    func removeAll() async throws { try await real.removeAll() }

    func protect(as protection: StorageProtection) async throws { try await real.protect(as: protection) }
}

private final class RecordingFileManager: FileManager {
    private let asked = Mutex<[FileProtectionType]>([])

    var requested: [FileProtectionType] { asked.withLock { $0 } }

    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        note(attributes)
        try super.setAttributes(attributes, ofItemAtPath: path)
    }

    override func createFile(atPath path: String, contents data: Data?, attributes: [FileAttributeKey: Any]?) -> Bool {
        note(attributes ?? [:])
        return super.createFile(atPath: path, contents: data, attributes: attributes)
    }

    private func note(_ attributes: [FileAttributeKey: Any]) {
        guard let protection = attributes[.protectionKey] as? FileProtectionType else { return }
        asked.withLock { $0.append(protection) }
    }
}
