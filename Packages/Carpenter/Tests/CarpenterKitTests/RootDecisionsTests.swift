import CarpenterKit
import Foundation
import Testing

@testable import CarpenterApp

@Suite("Composition root decisions")
@MainActor
struct RootDecisionsTests {
    // MARK: Which screen

    @Test("Every other state maps to exactly one screen")
    func everyStateHasAScreen() {
        #expect(RootScreen.for(.loading) == .loading)
        #expect(RootScreen.for(.checkingForRegistration) == .checkingForRegistration)
        #expect(RootScreen.for(.needsIdentity) == .onboarding(.newIdentity))
        #expect(RootScreen.for(.needsProfile) == .onboarding(.nameOnly))
        #expect(RootScreen.for(.ready) == .ready)
        #expect(RootScreen.for(.failed("no keychain")) == .failed("no keychain"))
    }

    // MARK: Starting device sync

    @Test("Device sync waits until there is a device to start it for")
    func noDeviceMeansWait() {
        #expect(DeviceSyncDecision.make(device: nil, startedFor: nil) == .wait)
    }

    @Test("Starting is idempotent for the same device")
    func idempotentForOneDevice() {
        let device = DeviceID(rawValue: Data(repeating: 7, count: 32))
        #expect(DeviceSyncDecision.make(device: device, startedFor: nil) == .start(device))
        #expect(DeviceSyncDecision.make(device: device, startedFor: device) == .alreadyRunning)
    }

    @Test("A different device starts a new engine")
    func aNewDeviceRestarts() {
        let old = DeviceID(rawValue: Data(repeating: 1, count: 32))
        let new = DeviceID(rawValue: Data(repeating: 2, count: 32))
        #expect(DeviceSyncDecision.make(device: new, startedFor: old) == .start(new))
    }

    // MARK: One round of sync

    @Test("A round refreshes device sync too, not only the mailbox")
    func deviceSyncIsPartOfARound() async {
        var refreshedDevices = false

        _ = await SyncRound.run(
            deviceSync: { refreshedDevices = true },
            mailbox: {},
)

        #expect(refreshedDevices, "a sync round left this member's own devices unasked")
    }

    @Test("A device-sync failure does not skip the mailbox")
    func deviceSyncFailureIsContained() async {
        var reachedMailbox = false

        let outcome = await SyncRound.run(
            deviceSync: { throw MailboxError.unavailable },
            mailbox: { reachedMailbox = true })

        #expect(reachedMailbox, "one failing half stopped the other from running")
        #expect(outcome.deviceSyncFailed)
        #expect(outcome.syncedAt != nil)
    }

    @Test("A mailbox failure leaves device sync's result standing")
    func mailboxFailureIsContained() async {
        var refreshedDevices = false

        let outcome = await SyncRound.run(
            deviceSync: { refreshedDevices = true },
            mailbox: { throw MailboxError.unavailable })

        #expect(refreshedDevices)
        #expect(outcome.mailboxFailed)
        #expect(outcome.syncedAt == nil)
    }

    @Test("Both working reports when it happened")
    func bothSucceed() async {
        let outcome = await SyncRound.run(deviceSync: {}, mailbox: {})

        #expect(outcome.syncedAt != nil)
        #expect(!outcome.mailboxFailed && !outcome.deviceSyncFailed)
    }

    @Test("A round asks about a deathmark before anything else, and stops there when it says erase")
    func theDeathmarkComesFirst() async {
        var order: [String] = []
        _ = await SyncRound.run(
            deathmark: { order.append("deathmark"); return false },
            deviceSync: { order.append("devices") },
            mailbox: { order.append("mailbox") })
        #expect(order == ["deathmark", "devices", "mailbox"])

        order = []
        let outcome = await SyncRound.run(
            deathmark: { order.append("deathmark"); return true },
            deviceSync: { order.append("devices") },
            mailbox: { order.append("mailbox") })
        #expect(order == ["deathmark"], "a device told to erase itself went on to touch iCloud")
        #expect(outcome.erased)
        #expect(outcome.syncedAt == nil)
    }

    @Test("Nothing that fails here is anything the member is shown")
    func failuresAreNotMemberFacing() async {
        let outcome = await SyncRound.run(
            deviceSync: { throw MailboxError.unavailable },
            mailbox: { throw MailboxError.unavailable })

        #expect(outcome.messageForMember == nil)
    }
}
