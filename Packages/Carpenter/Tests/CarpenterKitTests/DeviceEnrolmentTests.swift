import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@Suite("Device enrolment", .serialized)
@MainActor
struct DeviceEnrolmentTests {
    private func settle(_ session: AppSession, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return }
            await session.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func secondDevice(sharing keychain: InMemoryKeychainStore) async throws -> AppSession {
        try await keychain.remove(IdentityStore.deviceKey)
        let session = TestSession.make(keychain: keychain)
        await session.load()
        return session
    }

    // MARK: No setup

    @Test("A second device on the same account asks the member for nothing")
    func secondDeviceNeedsNoSetup() async throws {
        let keychain = InMemoryKeychainStore()

        let first = TestSession.make(keychain: keychain)
        await first.load()
        try await first.createIdentity(displayName: "Griff")

        let second = try await secondDevice(sharing: keychain)

        #expect(second.state == .needsProfile || second.state == .ready)
        #expect(second.enrolment != nil, "the second device did not enrol itself")
    }

    @Test("Both devices are the same member")
    func oneMemberTwoDevices() async throws {
        let keychain = InMemoryKeychainStore()

        let first = TestSession.make(keychain: keychain)
        await first.load()
        try await first.createIdentity(displayName: "Griff")

        let second = try await secondDevice(sharing: keychain)

        #expect(first.enrolment?.identity.id == second.enrolment?.identity.id)
    }

    @Test("The devices are still told apart")
    func devicesRemainDistinct() async throws {
        let keychain = InMemoryKeychainStore()

        let first = TestSession.make(keychain: keychain)
        await first.load()
        try await first.createIdentity(displayName: "Griff")

        let second = try await secondDevice(sharing: keychain)

        #expect(first.enrolment?.device.id != second.enrolment?.device.id)
    }

    @Test("Answering the name prompt late does not discard history that arrived meanwhile")
    func namingLateKeepsHistory() async throws {
        let keychain = InMemoryKeychainStore()
        let relay = InMemoryEntrySync.Relay()

        let first = TestSession.make(keychain: keychain)
        first.syncDevices(through: InMemoryEntrySync(relay: relay))
        await first.load()
        try await first.createIdentity(displayName: "Griff")
        let room = try await first.createRoom(named: "Kitchen")
        try await first.send("door code changed", to: room)

        let second = try await secondDevice(sharing: keychain)
        second.syncDevices(through: InMemoryEntrySync(relay: relay))
        await settle(second) {
            second.rooms.first?.name == "Kitchen"
                && second.messages(in: room).contains { $0.body == "door code changed" }
                && second.viewer.displayName == "Griff"
        }

        try await second.createIdentity(displayName: "Somebody Else")

        #expect(second.rooms.first?.name == "Kitchen", "answering the prompt discarded the history")
        #expect(second.messages(in: room).contains { $0.body == "door code changed" })
        #expect(second.viewer.displayName == "Griff", "a late answer renamed the member")
    }

    // MARK: Self-certification

    @Test("A new device issues its own certificate, and it verifies under the member's identity")
    func selfIssuedCertificateVerifies() async throws {
        let keychain = InMemoryKeychainStore()

        let first = TestSession.make(keychain: keychain)
        await first.load()
        try await first.createIdentity(displayName: "Griff")

        let second = try await secondDevice(sharing: keychain)
        let enrolment = try #require(second.enrolment)

        let certificate = try DeviceCertificate.issue(
            for: enrolment.device.publicKey, by: enrolment.identity, at: TestSession.now)

        var registry = DeviceRegistry(identity: enrolment.identity.publicKeys)
        try registry.admit(certificate)
        #expect(registry.isAuthorized(enrolment.device.id, at: TestSession.now))
    }

    @Test("A new device can write immediately, with nothing handed to it")
    func newDeviceCanWriteAtOnce() async throws {
        let keychain = InMemoryKeychainStore()

        let first = TestSession.make(keychain: keychain)
        await first.load()
        try await first.createIdentity(displayName: "Griff")

        let second = try await secondDevice(sharing: keychain)
        let room = try await second.createRoom(named: "Hangar 7")

        try await second.send("wrote this before syncing anything", to: room)
        #expect(second.messages(in: room).contains { $0.body == "wrote this before syncing anything" })
    }

    // MARK: History arrives by itself

    @Test("History reaches a new device with no handover")
    func historyArrivesWithoutAHandover() async throws {
        let keychain = InMemoryKeychainStore()
        let relay = InMemoryEntrySync.Relay()

        let first = TestSession.make(keychain: keychain)
        first.syncDevices(through: InMemoryEntrySync(relay: relay))
        await first.load()
        try await first.createIdentity(displayName: "Griff")

        let room = try await first.createRoom(named: "Kitchen")
        try await first.send("door code changed", to: room)

        let second = try await secondDevice(sharing: keychain)
        second.syncDevices(through: InMemoryEntrySync(relay: relay))
        await settle(second) {
            second.rooms.first?.name == "Kitchen"
                && second.messages(in: room).contains { $0.body == "door code changed" }
                && second.viewer.displayName == "Griff"
        }

        #expect(second.rooms.first?.name == "Kitchen")
        #expect(
            second.messages(in: room).contains { $0.body == "door code changed" },
            "the room key never arrived, so the room is there and unreadable")
        #expect(second.viewer.displayName == "Griff")
    }

    @Test("History from another device survives a relaunch")
    func historySurvivesARelaunch() async throws {
        let keychain = InMemoryKeychainStore()
        let relay = InMemoryEntrySync.Relay()
        let directory = URL.temporaryDirectory.appending(path: "relaunch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = TestSession.make(keychain: keychain)
        first.syncDevices(through: InMemoryEntrySync(relay: relay))
        await first.load()
        try await first.createIdentity(displayName: "Griff")
        let room = try await first.createRoom(named: "Kitchen")
        try await first.send("door code changed", to: room)

        try await keychain.remove(IdentityStore.deviceKey)
        let second = TestSession.make(keychain: keychain, at: directory)
        second.syncDevices(through: InMemoryEntrySync(relay: relay))
        await second.load()
        await settle(second) {
            second.rooms.first?.name == "Kitchen"
                && second.messages(in: room).contains { $0.body == "door code changed" }
        }

        try #require(second.messages(in: room).contains { $0.body == "door code changed" })

        var relaunched = TestSession.make(keychain: keychain, at: directory)
        await relaunched.load()

        func arrived(_ session: AppSession) -> Bool {
            session.rooms.first?.name == "Kitchen"
                && session.messages(in: room).contains { $0.body == "door code changed" }
        }

        let deadline = Date().addingTimeInterval(10)
        while !arrived(relaunched), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            relaunched = TestSession.make(keychain: keychain, at: directory)
            await relaunched.load()
        }

        #expect(relaunched.rooms.first?.name == "Kitchen")
        #expect(
            relaunched.messages(in: room).contains { $0.body == "door code changed" },
            "the sibling's entries were refused on relaunch, because its certificate was not kept")
    }

    @Test("A feed sealed by another member cannot even be opened")
    func aForeignFeedIsRefusedOutLoud() async throws {
        let keychain = InMemoryKeychainStore()
        let relay = InMemoryEntrySync.Relay()

        let mine = TestSession.make(keychain: keychain)
        mine.syncDevices(through: InMemoryEntrySync(relay: relay))
        await mine.load()
        try await mine.createIdentity(displayName: "Griff")

        let stranger = TestSession.make(keychain: InMemoryKeychainStore())
        let strangerSync = InMemoryEntrySync(relay: relay)
        stranger.syncDevices(through: strangerSync)
        await stranger.load()
        try await stranger.createIdentity(displayName: "Somebody Else")
        let room = try await stranger.createRoom(named: "Not Yours")
        try await stranger.send("not for you", to: room)

        await settle(mine) { mine.integrity.unreadableSiblingFeeds > 0 }

        #expect(
            mine.integrity.unreadableSiblingFeeds > 0,
            """
            A foreign feed was ignored in silence. Since the record is sealed under the member's own             identity, another member's feed does not open at all — which is why this counts as             unreadable rather than as somebody else's. The name check below is what catches a feed             that does open and still claims to be somebody else's.
            """)
        #expect(mine.messages(in: room).isEmpty, "another member's entries were integrated")
        #expect(mine.rooms.isEmpty)
    }

    @Test("A feed that opens and names somebody else is still refused")
    func aFeedNamingSomebodyElseIsRefused() async throws {
        let keychain = InMemoryKeychainStore()
        let relay = InMemoryEntrySync.Relay()

        let mine = TestSession.make(keychain: keychain)
        mine.syncDevices(through: InMemoryEntrySync(relay: relay))
        await mine.load()
        try await mine.createIdentity(displayName: "Griff")

        let identity = try #require(try await IdentityStore(keychain: keychain).loadIdentity())
        let device = DeviceID(rawValue: Data(repeating: 0xEE, count: 32))

        let impostor = InMemoryEntrySync(relay: relay)
        try await impostor.start()
        try await impostor.send(
            try SealedSiblingFeed.seal(
                SiblingFeed(
                    entries: [], certificates: [], epochs: [],
                    member: ParticipantID(rawValue: Data(repeating: 0x01, count: 32))),
                for: identity, on: device),
            from: device)

        await settle(mine) { mine.integrity.feedsFromOtherMembers > 0 }

        #expect(
            mine.integrity.feedsFromOtherMembers > 0,
            "a feed that opened and claimed another member was taken without complaint")
    }

    @Test("A feed that cannot say whose it is still has its entries verified, not discarded")
    func anUnattributedFeedIsStillVerified() async throws {
        let keychain = InMemoryKeychainStore()

        let writing = InMemoryEntrySync.Relay()
        let first = TestSession.make(keychain: keychain)
        let firstSync = InMemoryEntrySync(relay: writing)
        first.syncDevices(through: firstSync)
        await first.load()
        try await first.createIdentity(displayName: "Griff")
        let room = try await first.createRoom(named: "Kitchen")
        try await first.send("from an older build", to: room)

        let store = IdentityStore(keychain: keychain)
        let identity = try #require(try await store.loadIdentity())
        let firstDevice = try #require(try await store.loadDeviceKeys()).id

        let published = await firstSync.sent
            .compactMap { try? $0.open(with: identity, from: firstDevice) }
        let entries = published.flatMap(\.entries)
        let certificates = published.flatMap(\.certificates)
        let epochs = published.flatMap(\.epochs)

        let reading = InMemoryEntrySync.Relay()
        let second = try await secondDevice(sharing: keychain)
        second.syncDevices(through: InMemoryEntrySync(relay: reading))

        let legacyDevice = DeviceID(rawValue: Data(repeating: 0xCC, count: 32))
        let legacySibling = InMemoryEntrySync(relay: reading)
        try await legacySibling.start()
        try await legacySibling.send(
            try SealedSiblingFeed.seal(
                SiblingFeed(entries: entries, certificates: certificates, epochs: epochs),
                for: identity, on: legacyDevice),
            from: legacyDevice)

        await settle(second) { second.entryCount > 0 }

        #expect(second.entryCount > 0, "a feed from an older build was discarded, not verified")
        #expect(!second.rooms.isEmpty, "no room came out of a feed that was supposedly verified")
        #expect(
            second.integrity.feedsFromOtherMembers == 0,
            "a feed that merely could not name its member was counted as somebody else's")
    }

    @Test("What the new device writes is accepted by the old one")
    func theOldDeviceAcceptsTheNewOne() async throws {
        let keychain = InMemoryKeychainStore()
        let relay = InMemoryEntrySync.Relay()

        let first = TestSession.make(keychain: keychain)
        first.syncDevices(through: InMemoryEntrySync(relay: relay))
        await first.load()
        try await first.createIdentity(displayName: "Griff")
        let room = try await first.createRoom(named: "Kitchen")

        let second = try await secondDevice(sharing: keychain)
        second.syncDevices(through: InMemoryEntrySync(relay: relay))
        await settle(second) { !second.rooms.isEmpty }

        try await second.send("from the new device", to: room)
        await settle(first) {
            first.messages(in: room).contains { $0.body == "from the new device" }
        }

        #expect(
            first.messages(in: room).contains { $0.body == "from the new device" },
            "the first device rejected entries from a device it had not met")
    }
}
