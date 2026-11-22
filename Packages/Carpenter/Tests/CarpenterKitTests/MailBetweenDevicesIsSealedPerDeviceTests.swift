@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Mail that carries keys between a member's devices is never sealed under the identity alone")
struct MailBetweenDevicesIsSealedPerDeviceTests {
    @Test("Mail and a catch-up with no device to seal to are refused; a record with no keys in it is not")
    func noDeviceNoMail() throws {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        let feed = SiblingFeed(entries: [], certificates: [], member: identity.id)
        #expect(throws: (any Error).self) {
            try SealedSiblingFeed.seal(feed, for: identity, on: device.id, as: .mail(1), to: [])
        }
        #expect(throws: (any Error).self) {
            try SealedSiblingFeed.seal(feed, for: identity, on: device.id, as: .catchUp(for: DeviceKeys.generate().id), to: [])
        }
        _ = try SealedSiblingFeed.seal(feed, for: identity, on: device.id, as: .state, to: [])
    }
}

@MainActor
@Suite("A device with no receiving key does not make the others' mail readable by the identity alone", .serialized)
struct MailToADeviceWithoutAReceivingKeyTests {
    @Test("The mail is sealed to the devices that have a receiving key, and the identity alone cannot open it")
    func mailIsSealedToTheDevicesThatCanReceive() async throws {
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay()
        let session = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        session.syncDevices(through: InMemoryEntrySync(relay: relay))
        await session.load()
        try await session.createIdentity(displayName: "Griff")
        await session.settleDeviceSync()
        let enrolment = try #require(session.enrolment)

        clock.advance(by: 3600)
        let receiving = DeviceKeys.generate()
        try session.replica.admit(
            DeviceCertificate.issue(for: receiving, by: enrolment.identity, at: clock.now, approvedBy: enrolment.device))
        clock.advance(by: 3600)
        let older = DeviceKeys.generate()
        try session.replica.admit(
            DeviceCertificate.issue(
                for: older.publicKey, sealingKey: nil, by: enrolment.identity, at: clock.now,
                approvedBy: enrolment.device))
        for sibling in [receiving.id, older.id] {
            session.persisted.siblingMail.noteState(from: sibling, cursors: [], at: clock.now, me: enrolment.device.id)
        }

        _ = try await session.createRoom(named: "Kitchen")
        await session.settleDeviceSync()

        let mail = await relay.names(from: enrolment.device.id).filter {
            if case .mail = $0.kind { true } else { false }
        }
        try #require(!mail.isEmpty, "precondition: this device wrote mail for its others")
        let catchUps = await relay.names(from: enrolment.device.id).filter {
            if case .catchUp = $0.kind { true } else { false }
        }
        #expect(catchUps.map(\.kind) == [.catchUp(for: receiving.id)], "a catch-up went to a device it could not be sealed to")
        for name in mail + catchUps {
            let sealed = try #require(await relay.sealed(name))
            #expect(
                (try? sealed.open(with: enrolment.identity, from: name.writer, as: name.kind)) == nil,
                "mail carrying room keys opened with the identity alone")
            #expect((try? sealed.open(with: enrolment.identity, from: name.writer, as: name.kind, reading: receiving)) != nil)
        }
    }
}
