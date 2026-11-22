@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("When each person collected a message", .serialized)
struct WhenEachPersonCollectedItTests {
    private let keychain = InMemoryKeychainStore()
    private let folder = TestScratch.root.appending(path: "carpenter-collected-\(UUID().uuidString)")

    private func room() async throws -> (
        host: AppSession, bo: AppSession, nils: AppSession, room: RoomID, mailbox: InMemoryMailbox, clock: TestClock
    ) {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let host = TestSession.make(keychain: keychain, at: folder, clock: clock)
        let bo = TestSession.make(clock: clock)
        let nils = TestSession.make(clock: clock)
        for session in [host, bo, nils] { await session.load() }
        try await host.createIdentity(displayName: "Ada")
        try await bo.createIdentity(displayName: "Bo")
        try await nils.createIdentity(displayName: "Nils")
        let room = try await host.createRoom(named: "Hangar 7")
        for other in [bo, nils] {
            let invite = try await host.invite(
                joinerCode: await other.joinerCode(through: mailbox), joining: room, through: mailbox)
            try await other.redeem(inviteCode: try invite.encoded())
            try await host.sync(through: mailbox)
            try await other.accept(invite.attestation, from: try #require(host.enrolment?.identity.publicKeys))
            for _ in 0..<6 {
                for session in [host, bo, nils] { try await session.sync(through: mailbox) }
            }
        }
        try #require(host.roster(of: room).members.count == 3, "precondition: both are in")
        return (host, bo, nils, room, mailbox, clock)
    }

    @Test("A person's time is when iCloud stored their receipt, and only theirs is lit")
    func eachTimeIsTheirReceipt() async throws {
        let (host, bo, _, room, mailbox, clock) = try await room()
        try await host.send("doors at six", to: room)
        try await host.sync(through: mailbox)
        let message = try #require(host.messages(in: room).last { $0.body == "doors at six" })

        clock.advance(by: 600)
        let boCollected = clock.now
        try await bo.sync(through: mailbox)
        clock.advance(by: 3_600)
        try await host.sync(through: mailbox)

        let boID = try #require(bo.enrolment?.identity.id)
        let readers = host.readBy(message.id, in: room)
        let boTime = try #require(
            readers.first { $0.id == boID }?.collection.collectedAt, "Bo's receipt was in iCloud and no time was kept")
        #expect(
            boTime >= boCollected && boTime < boCollected.addingTimeInterval(1),
            "Bo's time was \(boTime), not when his receipt was stored at \(boCollected)")
        #expect(
            readers.filter { $0.id != boID }.allSatisfy { $0.collection == .noReceipt },
            "Nils never collected it, and his row said \(readers.map(\.collection))")
    }

    @Test("A receipt time is written down, so a relaunch neither loses it nor makes one up")
    func theTimeSurvivesARelaunch() async throws {
        let (host, bo, nils, room, mailbox, clock) = try await room()
        try await host.send("still on?", to: room)
        try await host.sync(through: mailbox)
        let message = try #require(host.messages(in: room).last { $0.body == "still on?" })
        clock.advance(by: 120)
        try await bo.sync(through: mailbox)
        try await nils.sync(through: mailbox)
        try await host.sync(through: mailbox)
        let before = host.readBy(message.id, in: room).map(\.collection)
        try #require(before.allSatisfy { $0.collectedAt != nil }, "precondition: both collected")

        let reopened = TestSession.make(keychain: keychain, at: folder, clock: clock)
        await reopened.load()
        #expect(reopened.readBy(message.id, in: room).map(\.collection) == before)
    }

    @Test("Only this phone's own messages, to people in the room they went to, are kept")
    func onlyOwnMessagesAreKept() async throws {
        let (host, bo, nils, room, mailbox, _) = try await room()
        try await bo.send("from Bo", to: room)
        try await host.send("from Ada", to: room)
        for _ in 0..<4 {
            for session in [host, bo, nils] { try await session.sync(through: mailbox) }
        }
        let mine = Set(host.replica.allEntries.filter { $0.author == host.enrolment?.identity.id }.map(\.hash))
        let kept = host.persisted.collectedAt.values.reduce(into: Set<EntryHash>()) { $0.formUnion($1.keys) }
        #expect(!kept.isEmpty, "precondition: something was collected")
        #expect(kept.isSubset(of: mine), "a receipt time was kept for an entry this phone did not write")
    }

    @Test("A copy taken back after the wait is not collected, and its row says so rather than a time")
    func aTakenBackCopyHasNoTime() async throws {
        let (host, bo, _, room, mailbox, clock) = try await room()
        try await host.send("are you there", to: room)
        try await host.sync(through: mailbox)
        let message = try #require(host.messages(in: room).last { $0.body == "are you there" })
        clock.advance(by: SyncSession.packetWaitsFor + 60)
        try await host.sync(through: mailbox)

        let boID = try #require(bo.enrolment?.identity.id)
        #expect(host.readBy(message.id, in: room).first { $0.id == boID }?.collection == .notCollected)
    }
}
