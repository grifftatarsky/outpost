@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Removing a device stops it reading the Outposts its member reads", .serialized)
struct ARemovedDeviceAndTheOutpostsItReadTests {
    private struct Reading {
        let yan: AppSession
        let griff: AppSession
        let spare: DeviceID
        let wall: RoomID
        let mailbox: InMemoryMailbox
    }

    private func settle(_ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func griffReadsYansOutpostOnTwoDevices() async throws -> Reading {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let yan = TestSession.make(clock: clock)
        let griff = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        for one in [yan, griff] { await one.load() }
        try await yan.createIdentity(displayName: "Yan")
        try await griff.createIdentity(displayName: "Griff")
        let room = try await yan.createRoom(named: "Lanterns")
        try await join(griff, into: room, of: yan, through: mailbox)

        clock.advance(by: 3600)
        let enrolment = try #require(griff.enrolment)
        let spare = DeviceKeys.generate()
        try griff.replica.admit(
            DeviceCertificate.issue(for: spare, by: enrolment.identity, at: clock.now, approvedBy: enrolment.device))

        try await yan.allowOutpost(enrolment.identity.id, everything: true)
        try await yan.send("before the removal", to: nil)
        try await settle([yan, griff], through: mailbox)

        let wall = yan.outpostRoom(for: try #require(yan.enrolment?.identity.id))
        try #require(griff.feed().map(\.body).contains("before the removal"), "precondition: Griff reads Yan's Outpost")
        try #require(
            yan.replica.registry(for: enrolment.identity.id)?.activeDevices.contains(spare.id) == true,
            "precondition: Yan knows Griff's second device")
        return Reading(yan: yan, griff: griff, spare: spare.id, wall: wall, mailbox: mailbox)
    }

    @Test("A reader's removal writes nothing into a friend's Outpost and keeps no key of its own for it")
    func noJunkKeyInAFriendsWall() async throws {
        let r = try await griffReadsYansOutpostOnTwoDevices()
        let held = r.griff.chains[r.wall]?.heldKeyCount
        let griffID = try #require(r.griff.enrolment?.identity.id)

        try await r.griff.revoke(r.spare)

        #expect(r.griff.chains[r.wall]?.heldKeyCount == held, "Griff made a key for Yan's Outpost")
        #expect(
            !r.griff.replica.allEntries.contains { $0.author == griffID && $0.room == r.wall },
            "Griff wrote a key change into Yan's Outpost")
    }

    @Test("The owner's next post does not open under any key the removed device held")
    func theOwnerRotatesWhenAReaderRemovesADevice() async throws {
        let r = try await griffReadsYansOutpostOnTwoDevices()
        let whatTheSpareHeld = try #require(r.griff.chains[r.wall])

        try await r.griff.revoke(r.spare)
        try await settle([r.griff, r.yan], through: r.mailbox)
        try await r.yan.send("after the removal", to: nil)
        try await settle([r.yan, r.griff], through: r.mailbox)

        let yanID = try #require(r.yan.enrolment?.identity.id)
        let post = try #require(r.yan.replica.allEntries.last { $0.author == yanID && $0.room == nil })
        #expect(post.opened(using: whatTheSpareHeld) == nil, "the removed device's keys open Yan's next post")
        #expect(r.griff.feed().map(\.body).contains("after the removal"), "Griff's remaining phone lost Yan's Outpost")
    }
}
