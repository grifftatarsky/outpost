import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@Suite("Failures that used to be silent")
struct SilentFailureTests {}

@MainActor
@Suite("Asking a Keychain that will not answer", .serialized)
struct UnreadableKeychainTests {
    private func session(
        _ keychain: any KeychainStore, hasMember: Bool
    ) -> AppSession {
        let session = TestSession.make(keychain: keychain)
        session.checkAccount(with: StubAccountRegistry(hasMember: hasMember))
        return session
    }

    @Test("A Keychain that stops answering mid-wait never offers to make a second member")
    func refusalDuringTheWaitDoesNotOfferOnboarding() async {
        let keychain = UnreadableKeychainStore(readable: true)
        let app = session(keychain, hasMember: false)
        await app.load()
        #expect(app.state == .checkingForRegistration)

        await keychain.becomeUnreadable()
        await app.settleRegistration(attempts: 2)

        #expect(
            app.state != .needsIdentity,
            "a Keychain that would not answer was read as an empty one, which is what makes two members")
    }

    @Test("A Keychain that answers, on the same empty account, does offer")
    func readableKeychainStillOffersOnboarding() async {
        let app = session(InMemoryKeychainStore(), hasMember: false)
        await app.load()
        await app.settleRegistration(attempts: 2)

        #expect(app.state == .needsIdentity, "an ordinary first run stopped reaching onboarding")
    }

    @Test("It moves on once the Keychain answers again")
    func unlockingEndsTheWait() async {
        let keychain = UnreadableKeychainStore(readable: true)
        let app = session(keychain, hasMember: false)
        await app.load()
        await keychain.becomeUnreadable()
        await app.settleRegistration(attempts: 2)
        #expect(app.state == .registrationStalled(.keychainUnreadable))

        await keychain.becomeReadable()
        await app.settleRegistration(attempts: 2)

        #expect(
            app.state == .needsIdentity,
            "the device never stopped waiting on a Keychain that started answering again")
    }

    @Test("A refused read is not a device without a member")
    func recheckDoesNotTreatRefusalAsAbsence() async {
        let keychain = UnreadableKeychainStore(readable: true)
        let app = session(keychain, hasMember: true)
        await app.load()
        await keychain.becomeUnreadable()

        #expect(await app.recheckForSyncedIdentity() == false)
        #expect(app.state != .needsIdentity, "a refused read moved the device on to onboarding")
    }

    @Test("A Keychain that refuses from the start fails visibly instead")
    func refusalAtLoadIsAlreadyVisible() async {
        let app = session(UnreadableKeychainStore(), hasMember: false)
        await app.load()

        guard case .failed = app.state else {
            Issue.record("a Keychain that refused at load did not reach the failure screen")
            return
        }
    }
}

@MainActor
@Suite("Revoking a device that cannot turn the key", .serialized)
struct RevocationReportingTests {
    private func pair(
        keychain: any KeychainStore
    ) async throws -> (first: AppSession, second: AppSession, other: DeviceID) {
        let relay = InMemoryEntrySync.Relay()

        let first = TestSession.make(keychain: keychain)
        first.syncDevices(through: InMemoryEntrySync(relay: relay))
        await first.load()
        try await first.createIdentity(displayName: "Griff")

        try await keychain.remove(IdentityStore.deviceKey)
        let second = TestSession.make(keychain: keychain)
        second.syncDevices(through: InMemoryEntrySync(relay: relay))
        await second.load()

        let other = try #require(second.enrolment?.device.id)

        try await second.setDisplayName("Griff")

        let deadline = Date().addingTimeInterval(5)
        while first.devices.count < 2, Date() < deadline {
            await second.refreshDeviceSync()
            await first.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
        try #require(first.devices.count == 2, "the second device's certificate never arrived")

        return (first, second, other)
    }

    @Test("A revocation that turns every key raises nothing")
    func cleanRevocationDoesNotThrow() async throws {
        let (first, _, other) = try await pair(keychain: InMemoryKeychainStore())
        let room = try await first.createRoom(named: "Kitchen")
        let before = try #require(first.epoch(of: room))

        try await first.revoke(other)

        let after = try #require(first.epoch(of: room))
        #expect(after > before, "revoking did not turn the room's key")
    }

    @Test("A key that cannot be turned is said, not swallowed")
    func keyThatCannotTurnIsReported() async throws {
        let keychain = HalfWritableKeychainStore()
        let (first, _, other) = try await pair(keychain: keychain)
        _ = try await first.createRoom(named: "Kitchen")

        await keychain.stopAcceptingWrites()

        do {
            try await first.revoke(other)
            Issue.record("the key could not be turned and nothing was raised")
        } catch let error as AppSessionError {
            guard case .keyNotTurned(let rooms) = error else {
                Issue.record("raised \(error) rather than naming the half that failed")
                return
            }
            #expect(rooms >= 1, "the error did not say how many rooms went unturned")
        }
    }

    @Test("The device is revoked even when its rooms' keys did not turn")
    func theRevocationItselfStillHolds() async throws {
        let keychain = HalfWritableKeychainStore()
        let (first, _, other) = try await pair(keychain: keychain)
        _ = try await first.createRoom(named: "Kitchen")
        await keychain.stopAcceptingWrites()

        _ = try? await first.revoke(other)

        #expect(
            first.devices.first { $0.id == other }?.isActive == false,
            "the device was left active by the failure of the half that comes after it")
    }
}

actor HalfWritableKeychainStore: KeychainStore {
    struct Full: Error {}

    private var items: [KeychainKey: Data] = [:]
    private var accepting = true

    func stopAcceptingWrites() { accepting = false }

    func data(for key: KeychainKey) throws -> Data? { items[key] }

    func set(_ data: Data, for key: KeychainKey, scope: KeychainScope) throws {
        guard accepting else { throw Full() }
        items[key] = data
    }

    func remove(_ key: KeychainKey) throws { items[key] = nil }
    func removeAll() throws { items = [:] }
}
