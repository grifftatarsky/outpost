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

    private func firstDevice(
        _ keychain: InMemoryKeychainStore, on relay: InMemoryEntrySync.Relay
    ) async throws -> AppSession {
        let first = TestSession.make(keychain: keychain)
        first.syncDevices(through: InMemoryEntrySync(relay: relay))
        await first.load()
        try await first.createIdentity(displayName: "Griff")
        return first
    }

    private func waitingDevice(
        sharing keychain: InMemoryKeychainStore, on relay: InMemoryEntrySync.Relay, at directory: URL? = nil
    ) async -> AppSession {
        let second = TestSession.make(keychain: await keychain.sibling(), at: directory)
        second.syncDevices(through: InMemoryEntrySync(relay: relay))
        await second.load()
        second.checkAccount(with: StubAccountRegistry(hasMember: true))
        await second.settleRegistration()
        return second
    }

    private func approvedDevice(
        of first: AppSession, sharing keychain: InMemoryKeychainStore, on relay: InMemoryEntrySync.Relay,
        at directory: URL? = nil
    ) async throws -> AppSession {
        let second = await waitingDevice(sharing: keychain, on: relay, at: directory)
        try await first.approveNewDevice(second)
        return second
    }

    // MARK: Approval

    @Test("A second device waits until one of the member's other devices approves it")
    func aSecondDeviceWaitsForApproval() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let first = try await firstDevice(keychain, on: relay)

        let second = await waitingDevice(sharing: keychain, on: relay)
        #expect(second.state == .awaitingApproval)
        #expect(second.enrolment == nil, "the new device acted as the member before anybody approved it")

        try await first.approveNewDevice(second)
        #expect(second.state == .needsProfile || second.state == .ready)
        #expect(second.enrolment != nil)
    }

    @Test("The code the new device shows is the code the approving device shows")
    func bothDevicesShowTheSameCode() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let first = try await firstDevice(keychain, on: relay)
        let second = await waitingDevice(sharing: keychain, on: relay)

        await first.settleDeviceSync { !first.deviceRequests.isEmpty }
        let shown = try #require(second.approvalCode)
        #expect(shown.count == DeviceRequest.codeLength)
        #expect(first.deviceRequests.map(\.code) == [shown])
    }

    @Test("A device that is not approved can't write anything")
    func aWaitingDeviceCannotWrite() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        _ = try await firstDevice(keychain, on: relay)
        let second = await waitingDevice(sharing: keychain, on: relay)

        await #expect(throws: (any Error).self, "a device nobody approved made a room") {
            _ = try await second.createRoom(named: "Hangar 7")
        }
    }

    @Test("Declining leaves the new device waiting, and the request stops showing")
    func decliningLeavesItWaiting() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let first = try await firstDevice(keychain, on: relay)
        let second = await waitingDevice(sharing: keychain, on: relay)
        await first.settleDeviceSync { !first.deviceRequests.isEmpty }
        let request = try #require(first.deviceRequests.first)

        await first.declineDevice(request)
        await first.settleDeviceSync()
        await second.settleDeviceSync()

        #expect(first.deviceRequests.isEmpty)
        #expect(second.state == .awaitingApproval)
        #expect(second.enrolment == nil)
    }

    @Test("A device without the member's key in its Keychain is handed it when approved")
    func aDeviceWithoutTheKeyIsHandedIt() async throws {
        let relay = InMemoryEntrySync.Relay()
        let first = try await firstDevice(InMemoryKeychainStore(), on: relay)

        let second = TestSession.make(keychain: InMemoryKeychainStore())
        second.checkAccount(with: StubAccountRegistry(hasMember: true))
        second.syncDevices(through: InMemoryEntrySync(relay: relay))
        await second.load()
        await second.settleRegistration(attempts: 2)
        #expect(second.state == .awaitingApproval, "an occupied account without the key did not ask for approval")

        try await first.approveNewDevice(second)
        #expect(second.enrolment?.identity.id == first.enrolment?.identity.id)
    }

    @Test("Both devices are the same member, and are still told apart")
    func oneMemberTwoDevices() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let first = try await firstDevice(keychain, on: relay)
        let second = try await approvedDevice(of: first, sharing: keychain, on: relay)

        #expect(first.enrolment?.identity.id == second.enrolment?.identity.id)
        #expect(first.enrolment?.device.id != second.enrolment?.device.id)
    }

    @Test("An approved device's certificate names the device that approved it")
    func theApproverIsNamed() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let first = try await firstDevice(keychain, on: relay)
        let second = try await approvedDevice(of: first, sharing: keychain, on: relay)
        let identity = try #require(first.enrolment?.identity.id)
        let secondDevice = try #require(second.enrolment?.device.id)

        let registry = try #require(first.replica.registry(for: identity))
        #expect(registry.standing(of: secondDevice)?.approvedBy == first.enrolment?.device.id)
        #expect(second.replica.registry(for: identity)?.standing(of: secondDevice) != nil)
    }

    @Test("Answering the name prompt late does not discard history that arrived meanwhile")
    func namingLateKeepsHistory() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let first = try await firstDevice(keychain, on: relay)
        let room = try await first.createRoom(named: "Kitchen")
        try await first.send("door code changed", to: room)

        let second = try await approvedDevice(of: first, sharing: keychain, on: relay)
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

    @Test("An approved device can write at once")
    func anApprovedDeviceCanWriteAtOnce() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let first = try await firstDevice(keychain, on: relay)
        let second = try await approvedDevice(of: first, sharing: keychain, on: relay)
        let room = try await second.createRoom(named: "Hangar 7")

        try await second.send("wrote this before syncing anything", to: room)
        #expect(second.messages(in: room).contains { $0.body == "wrote this before syncing anything" })
    }

    // MARK: History arrives by itself

    @Test("History reaches a new device once it is approved")
    func historyArrivesOnceApproved() async throws {
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let first = try await firstDevice(keychain, on: relay)
        let room = try await first.createRoom(named: "Kitchen")
        try await first.send("door code changed", to: room)

        let second = try await approvedDevice(of: first, sharing: keychain, on: relay)
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
        let (keychain, relay) = (InMemoryKeychainStore(), InMemoryEntrySync.Relay())
        let directory = URL.temporaryDirectory.appending(path: "relaunch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try await firstDevice(keychain, on: relay)
        let room = try await first.createRoom(named: "Kitchen")
        try await first.send("door code changed", to: room)

        let secondKeychain = await keychain.sibling()
        let second = TestSession.make(keychain: secondKeychain, at: directory)
        second.syncDevices(through: InMemoryEntrySync(relay: relay))
        await second.load()
        try await first.approveNewDevice(second)
        await settle(second) {
            second.rooms.first?.name == "Kitchen"
                && second.messages(in: room).contains { $0.body == "door code changed" }
        }
        try #require(second.messages(in: room).contains { $0.body == "door code changed" })

        func arrived(_ session: AppSession) -> Bool {
            session.rooms.first?.name == "Kitchen"
                && session.messages(in: room).contains { $0.body == "door code changed" }
        }

        var relaunched = TestSession.make(keychain: secondKeychain, at: directory)
        await relaunched.load()
        let deadline = Date().addingTimeInterval(10)
        while !arrived(relaunched), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            relaunched = TestSession.make(keychain: secondKeychain, at: directory)
            await relaunched.load()
        }

        #expect(relaunched.state != .awaitingApproval, "a relaunch forgot that this device was approved")
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
            [SiblingRecord(
                name: SiblingRecord.Name(writer: device, kind: .state),
                sealed: try SealedSiblingFeed.seal(
                    SiblingFeed(
                        entries: [], certificates: [], epochs: [],
                        member: ParticipantID(rawValue: Data(repeating: 0x01, count: 32))),
                    for: identity, on: device))],
            deleting: [])

        await settle(mine) { mine.integrity.feedsFromOtherMembers > 0 }

        #expect(
            mine.integrity.feedsFromOtherMembers > 0,
            "a feed that opened and claimed another member was taken without complaint")
    }

    @Test("A feed that cannot say whose it is still has its entries verified, not discarded")
    func anUnattributedFeedIsStillVerified() async throws {
        let keychain = InMemoryKeychainStore()
        let writing = InMemoryEntrySync.Relay()
        let first = try await firstDevice(keychain, on: writing)
        let second = try await approvedDevice(of: first, sharing: keychain, on: writing)
        let reading = InMemoryEntrySync.Relay()
        second.syncDevices(through: InMemoryEntrySync(relay: reading))

        let room = try await first.createRoom(named: "Kitchen")
        try await first.send("from an older build", to: room)

        let identity = try #require(first.enrolment?.identity)
        let firstDevice = try #require(first.enrolment?.device.id)
        let entries = first.replica.allEntries.filter { $0.device == firstDevice }
        let certificates = first.knownCertificates()
        let epochs = first.chains.flatMap { room, chain in
            chain.knownEpochs.compactMap { epoch in
                (try? chain.secret(for: epoch)).map {
                    HeldEpoch(room: room, epoch: epoch, material: $0.material)
                }
            }
        }

        let legacyDevice = DeviceID(rawValue: Data(repeating: 0xCC, count: 32))
        let legacySibling = InMemoryEntrySync(relay: reading)
        try await legacySibling.start()
        try await legacySibling.send(
            [SiblingRecord(
                name: SiblingRecord.Name(writer: legacyDevice, kind: .state),
                sealed: try SealedSiblingFeed.seal(
                    SiblingFeed(entries: entries, certificates: certificates, epochs: epochs),
                    for: identity, on: legacyDevice))],
            deleting: [])

        await settle(second) { second.messages(in: room).contains { $0.body == "from an older build" } }

        #expect(
            second.messages(in: room).contains { $0.body == "from an older build" },
            "a feed from an older build was discarded, not verified")
        #expect(
            second.integrity.feedsFromOtherMembers == 0,
            "a feed that merely could not name its member was counted as somebody else's")
    }

    @Test("What the new device writes is accepted by the old one")
    func theOldDeviceAcceptsTheNewOne() async throws {
        let keychain = InMemoryKeychainStore()
        let relay = InMemoryEntrySync.Relay()

        let first = try await firstDevice(keychain, on: relay)
        let room = try await first.createRoom(named: "Kitchen")

        let second = try await approvedDevice(of: first, sharing: keychain, on: relay)
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
