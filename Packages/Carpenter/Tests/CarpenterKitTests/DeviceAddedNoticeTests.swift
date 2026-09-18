@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Somebody you talk to adding a device is said in the conversation, with its date", .serialized)
struct DeviceAddedNoticeTests {
    private func addedDevices(_ session: AppSession, _ room: RoomID) -> [(ParticipantID, Date)] {
        session.transcript(in: room).compactMap { item in
            guard case .notice(let notice) = item, case .addedADevice(let who) = notice.kind
            else { return nil }
            return (who.id, notice.at)
        }
    }

    @Test("A second phone of Bob's reaches Alice as a dated line, and his first phone never does")
    func aSecondPhoneIsSaid() async throws {
        let mailbox = InMemoryMailbox()
        let relay = InMemoryEntrySync.Relay()
        let clock = TestClock(now: TestSession.now)
        let bobKeychain = InMemoryKeychainStore()

        let alice = TestSession.make(clock: clock)
        let bob = TestSession.make(keychain: bobKeychain, clock: clock)
        bob.syncDevices(through: InMemoryEntrySync(relay: relay))
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await join(bob, into: room, of: alice, through: mailbox)
        try await bob.send("from my first phone", to: room)
        for _ in 0..<3 {
            try await bob.sync(through: mailbox)
            try await alice.sync(through: mailbox)
        }
        #expect(addedDevices(alice, room).isEmpty, "the phone Bob joined with was called an added device")

        clock.advance(by: 86_400)
        try await bobKeychain.remove(IdentityStore.deviceKey)
        let bobsSecond = TestSession.make(keychain: bobKeychain, clock: clock)
        bobsSecond.syncDevices(through: InMemoryEntrySync(relay: relay))
        await bobsSecond.load()
        let deadline = Date().addingTimeInterval(5)
        while bob.devices.count < 2, Date() < deadline {
            await bob.refreshDeviceSync()
            await bobsSecond.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
        try #require(bob.devices.count == 2, "precondition: Bob's first phone learned of the second")

        try await bob.send("I have a new phone as well", to: room)
        for _ in 0..<4 {
            try await bob.sync(through: mailbox)
            try await alice.sync(through: mailbox)
        }
        #expect(alice.messages(in: room).map(\.body).contains("I have a new phone as well"))

        let said = addedDevices(alice, room)
        #expect(said.count == 1, "expected one added device, saw \(said.count)")
        #expect(said.first?.0 == bob.enrolment?.identity.id)
        #expect(said.first?.1 == clock.now, "the line is dated by the device's own certificate")

        let transcript = alice.transcript(in: room)
        let lineAt = transcript.firstIndex { if case .notice(let n) = $0, case .addedADevice = n.kind { return true } else { return false } }
        let newPhoneAt = transcript.firstIndex { $0.message?.body == "I have a new phone as well" }
        #expect(
            (lineAt ?? .max) < (newPhoneAt ?? .min),
            "the line came after a message sent once the phone existed")
        #expect(
            alice.devicesAdded(by: try #require(bob.enrolment?.identity.id), after: TestSession.now).count == 1)
    }
}
