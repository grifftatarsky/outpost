import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp

@Suite("Restoring a member from their recovery key", .serialized)
@MainActor
struct RestoringFromAKeyTests {
    private func settle(_ session: AppSession, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return }
            await session.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    @Test("A key puts the same member back on a fresh device")
    func aKeyPutsTheSameMemberBack() async throws {
        let original = TestSession.make(keychain: InMemoryKeychainStore())
        await original.load()
        try await original.createIdentity(displayName: "Griff")

        let key = try #require(original.recoveryKeyText())
        let who = try #require(original.enrolment?.identity.id)

        let fresh = TestSession.make(keychain: InMemoryKeychainStore())
        await fresh.load()
        try await fresh.restore(fromRecoveryKey: key)

        #expect(fresh.enrolment?.identity.id == who, "the restored device is a different member")
        #expect(fresh.state == AppSession.State.ready)
    }

    @Test("The restored device is a new device, not the old one")
    func theRestoredDeviceIsANewDevice() async throws {
        let original = TestSession.make(keychain: InMemoryKeychainStore())
        await original.load()
        try await original.createIdentity(displayName: "Griff")

        let key = try #require(original.recoveryKeyText())
        let oldDevice = try #require(original.enrolment?.device.id)

        let fresh = TestSession.make(keychain: InMemoryKeychainStore())
        await fresh.load()
        try await fresh.restore(fromRecoveryKey: key)

        #expect(
            fresh.enrolment?.device.id != oldDevice,
            """
            The restored device reused the lost device's key. A device key is `scope: .device` and \
            never travels; if this passes it means the key file is carrying one.
            """)
    }

    @Test("History comes back from the member's own other device")
    func historyComesBackFromTheirOwnOtherDevice() async throws {
        let keychain = InMemoryKeychainStore()
        let relay = InMemoryEntrySync.Relay()

        let original = TestSession.make(keychain: keychain)
        original.syncDevices(through: InMemoryEntrySync(relay: relay))
        await original.load()
        try await original.createIdentity(displayName: "Griff")
        let room = try await original.createRoom(named: "Kitchen")
        try await original.send("the tap is dripping again", to: room)

        let key = try #require(original.recoveryKeyText())

        let fresh = TestSession.make(keychain: InMemoryKeychainStore())
        fresh.syncDevices(through: InMemoryEntrySync(relay: relay))
        await fresh.load()
        try await fresh.restore(fromRecoveryKey: key)

        await settle(fresh) { !fresh.rooms.isEmpty }

        #expect(!fresh.rooms.isEmpty, "no room came back from the member's own other device")
        #expect(
            fresh.messages(in: room).contains { $0.body == "the tap is dripping again" },
            "the room came back and what was said in it did not")
    }

    @Test("A restored device asks its peers for what was said, without being told to")
    func aRestoredDeviceAsksItsPeers() async throws {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay()

        let original = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        let peer = TestSession.make(clock: clock)
        original.syncDevices(through: InMemoryEntrySync(relay: relay))
        for session in [original, peer] { await session.load() }
        try await original.createIdentity(displayName: "Griff")
        try await peer.createIdentity(displayName: "Outie")

        let room = try await original.createRoom(named: "Kitchen")
        let invite = try await original.invite(
            joinerCode: peer.identityCode(), joining: room, mailbox: nil)
        try await peer.redeem(inviteCode: try invite.encoded())
        try await original.sync(through: mailbox)
        try await peer.accept(
            invite.attestation, from: try #require(original.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [original, peer] { try await session.sync(through: mailbox) }
        }

        await settle(original) { false }
        let key = try #require(original.recoveryKeyText())

        try await peer.send("said while the phone was gone", to: room)
        for _ in 0..<6 {
            for session in [original, peer] { try await session.sync(through: mailbox) }
        }
        #expect(
            original.messages(in: room).contains { $0.body == "said while the phone was gone" },
            "the peer never delivered it to the device that was later lost")

        let fresh = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        fresh.syncDevices(through: InMemoryEntrySync(relay: relay))
        await fresh.load()
        try await fresh.restore(fromRecoveryKey: key)
        await settle(fresh) { !fresh.rooms.isEmpty }

        for _ in 0..<10 {
            for session in [fresh, peer] { try await session.sync(through: mailbox) }
        }

        #expect(
            fresh.messages(in: room).contains { $0.body == "said while the phone was gone" },
            """
            A restored device never got what its peer still held. The peer will not re-offer it \
            — an entry goes into a packet once and its frontier says this was already sent — so \
            the restored device has to raise a repair by itself. Before 2026-09-13 nothing did: \
            `startRepair` was only ever reached by a member tapping a control in room details, \
            so on the rig `entriesReceived` was 0 on every round while the peer wrote \
            `unsent=0`, and the suite was green the whole time.
            """)
    }

    @Test("A device that already has a member refuses a key")
    func aDeviceThatAlreadyHasAMemberRefusesAKey() async throws {
        let original = TestSession.make(keychain: InMemoryKeychainStore())
        await original.load()
        try await original.createIdentity(displayName: "Griff")
        let key = try #require(original.recoveryKeyText())

        let occupied = TestSession.make(keychain: InMemoryKeychainStore())
        await occupied.load()
        try await occupied.createIdentity(displayName: "Somebody Else")
        let theirs = try #require(occupied.enrolment?.identity.id)

        await #expect(throws: AppSession.RestoreFailure.thisDeviceAlreadyHasAMember) {
            try await occupied.restore(fromRecoveryKey: key)
        }
        #expect(
            occupied.enrolment?.identity.id == theirs,
            "a refused restore still moved the member on this device")
    }

    @Test("Each way a key can be wrong says which way")
    func eachWayAKeyCanBeWrongSaysWhichWay() async throws {
        let original = TestSession.make(keychain: InMemoryKeychainStore())
        await original.load()
        try await original.createIdentity(displayName: "Griff")
        let key = try #require(original.recoveryKeyText())

        func restoring(_ text: String) async -> AppSession.RestoreFailure? {
            let fresh = TestSession.make(keychain: InMemoryKeychainStore())
            await fresh.load()
            do {
                try await fresh.restore(fromRecoveryKey: text)
                return nil
            } catch let failure as AppSession.RestoreFailure {
                return failure
            } catch {
                return nil
            }
        }

        #expect(
            await restoring("a shopping list") == .keyRefused(.notARecoveryKey),
            "something that is not a recovery key at all was not named as such")
        #expect(
            await restoring(key.replacingOccurrences(of: " v1", with: " v99"))
                == .keyRefused(.fromANewerVersion(99)),
            "a key from a newer build was read rather than refused with its version")
        #expect(
            await restoring(String(key.dropLast(12))) == .keyRefused(.damaged),
            """
            A key whose CHECK line was cut off was accepted. The checksum is the only thing that             catches a file mangled by copy and paste, so it has to be required rather than             honoured when present.
            """)
        #expect(
            await restoring(key.replacingOccurrences(of: "SIGNING: ", with: "SIGNING: A"))
                == .keyRefused(.damaged),
            "a key with a changed seed was accepted")
    }
}
