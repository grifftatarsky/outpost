@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Erasing everything reaches every device the member had", .serialized)
@MainActor
struct DeathmarkTests {
    private struct Household {
        let phone: AppSession
        let tablet: AppSession
        let relay: InMemoryEntrySync.Relay
        let clock: TestClock
        let board: InMemoryDeathmarkBoard
    }

    private func household() async throws -> Household {
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay()
        let phone = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        await phone.load()
        try await phone.createIdentity(displayName: "Griff")
        await phone.settleDeviceSync()
        let tablet = try await approved(by: phone, relay: relay, clock: clock)
        return Household(
            phone: phone, tablet: tablet, relay: relay, clock: clock, board: InMemoryDeathmarkBoard(clock: clock))
    }

    private func approved(by device: AppSession, relay: InMemoryEntrySync.Relay, clock: TestClock) async throws
        -> AppSession
    {
        clock.advance(by: 60)
        let joining = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        joining.syncDevices(through: InMemoryEntrySync(relay: relay))
        await joining.load()
        try await device.approveNewDevice(joining)
        for session in [device, joining] {
            await session.refreshDeviceSync()
            await session.settleDeviceSync()
        }
        clock.advance(by: 60)
        return joining
    }

    @Test("A device on the list obeys the deathmark another device left, and the last one clears it")
    func theOtherDeviceObeys() async throws {
        let home = try await household()
        try await home.phone.leaveDeathmark(on: home.board)
        #expect(await home.board.isPosted)
        #expect(await home.tablet.obeyDeathmark(on: home.board) == .eraseThisDevice, "the tablet carried on")
        #expect(!(await home.board.isPosted), "the last device to erase itself left the deathmark behind")
    }

    @Test("The device that left it finishes erasing itself if it stopped partway")
    func theIssuerFinishesTheJob() async throws {
        let home = try await household()
        try await home.phone.leaveDeathmark(on: home.board)
        #expect(await home.phone.obeyDeathmark(on: home.board) == .eraseThisDevice)
        #expect(await home.board.isPosted, "the phone cleared it before the tablet heard")
    }

    @Test("A device that is not the last to obey leaves the deathmark for the others")
    func notLastLeavesItStanding() async throws {
        let home = try await household()
        let laptop = try await approved(by: home.phone, relay: home.relay, clock: home.clock)
        for session in [home.phone, home.tablet] {
            await session.refreshDeviceSync()
            await session.settleDeviceSync()
        }
        try await home.phone.leaveDeathmark(on: home.board)
        #expect(await home.tablet.obeyDeathmark(on: home.board) == .eraseThisDevice)
        #expect(await home.board.isPosted, "the deathmark went before the laptop heard it")
        #expect(await laptop.obeyDeathmark(on: home.board) == .eraseThisDevice)
        #expect(!(await home.board.isPosted))
    }

    @Test("A device added after the deathmark, or restored with the recovery key, is not on the list and carries on")
    func laterDevicesCarryOn() async throws {
        let home = try await household()
        try await home.phone.leaveDeathmark(on: home.board)
        let later = try await approved(by: home.tablet, relay: home.relay, clock: home.clock)
        #expect(await later.obeyDeathmark(on: home.board) == .carryOn, "a device the deathmark never named erased itself")
    }

    @Test("A removed device can't leave a deathmark the member's devices obey")
    func aRemovedDeviceCannotNuke() async throws {
        let home = try await household()
        let stolen = try await approved(by: home.phone, relay: home.relay, clock: home.clock)
        let stolenKeys = try #require(stolen.enrolment?.device)
        let identity = try #require(stolen.enrolment?.identity)
        let everyone = try #require(home.phone.replica.registry(for: identity.id)?.activeDevices)
        try await home.phone.revoke(stolenKeys.id)
        for session in [home.phone, home.tablet] {
            await session.refreshDeviceSync()
            await session.settleDeviceSync()
        }
        home.clock.advance(by: 120)
        let fromTheStolenPhone = try Deathmark.issue(
            for: identity.id, listing: everyone, by: stolenKeys, at: home.clock.now)
        await home.board.overwrite(with: try fromTheStolenPhone.sealed(for: identity), storedAt: home.clock.now)
        #expect(await home.tablet.obeyDeathmark(on: home.board) == .carryOn, "a removed device erased the tablet")
        #expect(await home.phone.obeyDeathmark(on: home.board) == .carryOn, "a removed device erased the phone")
    }

    @Test("A deathmark altered, sealed for somebody else, or from a stranger's device is ignored")
    func forgeriesAreIgnored() async throws {
        let home = try await household()
        let me = try #require(home.tablet.enrolment?.identity)
        let tabletID = try #require(home.tablet.enrolment?.device.id)

        let stranger = DeviceKeys.generate()
        let fromAStranger = try Deathmark.issue(for: me.id, listing: [tabletID], by: stranger, at: home.clock.now)
        await home.board.overwrite(with: try fromAStranger.sealed(for: me), storedAt: home.clock.now)
        #expect(await home.tablet.obeyDeathmark(on: home.board) == .carryOn, "a stranger's device erased the tablet")

        let someoneElse = Identity.generate()
        let phoneKeys = try #require(home.phone.enrolment?.device)
        let elsewhere = try Deathmark.issue(for: someoneElse.id, listing: [tabletID], by: phoneKeys, at: home.clock.now)
        await home.board.overwrite(with: try elsewhere.sealed(for: someoneElse), storedAt: home.clock.now)
        #expect(await home.tablet.obeyDeathmark(on: home.board) == .carryOn, "another member's deathmark erased the tablet")

        let genuine = try Deathmark.issue(for: me.id, listing: [tabletID], by: phoneKeys, at: home.clock.now)
        var bytes = try genuine.sealed(for: me)
        bytes[bytes.index(before: bytes.endIndex)] ^= 0x01
        await home.board.overwrite(with: bytes, storedAt: home.clock.now)
        #expect(await home.tablet.obeyDeathmark(on: home.board) == .carryOn, "an altered deathmark erased the tablet")

        let listed = try Deathmark.issue(for: me.id, listing: [tabletID], by: phoneKeys, at: home.clock.now)
        let forged = Deathmark(
            member: listed.member, issuedBy: listed.issuedBy, devices: [tabletID, DeviceKeys.generate().id],
            issuedAt: listed.issuedAt, signature: listed.signature)
        await home.board.overwrite(with: try forged.sealed(for: me), storedAt: home.clock.now)
        #expect(await home.tablet.obeyDeathmark(on: home.board) == .carryOn, "a list changed after signing was obeyed")

        await home.board.overwrite(with: try genuine.sealed(for: me), storedAt: home.clock.now)
        #expect(await home.tablet.obeyDeathmark(on: home.board) == .eraseThisDevice, "precondition: the genuine one works")
    }

    @Test("Before its approval was stored, a device could not have left one")
    func storedBeforeTheSignerCounted() async throws {
        let home = try await household()
        let me = try #require(home.phone.enrolment?.identity)
        let phoneID = try #require(home.phone.enrolment?.device.id)
        let tabletKeys = try #require(home.tablet.enrolment?.device)
        let early = try Deathmark.issue(for: me.id, listing: [phoneID], by: tabletKeys, at: TestSession.now)
        await home.board.overwrite(with: try early.sealed(for: me), storedAt: TestSession.now)
        #expect(await home.phone.obeyDeathmark(on: home.board) == .carryOn)
    }
}
