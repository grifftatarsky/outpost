@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "A tablet restarts before its disk recovers", .serialized, .timeLimit(.minutes(10)),
    .tags(.sync, .manyDevices))
struct ATabletRestartsBeforeItsDiskRecoversTests {
    private func tablet(_ log: MemoryLogStore, _ keychain: InMemoryKeychainStore, _ folder: URL, _ clock: TestClock)
        -> AppSession
    {
        AppSession(
            storage: SessionStorage(
                keychain: keychain, log: log, documents: FileDocumentStore(url: folder.appending(path: "state.json"))),
            clock: clock)
    }

    private func refreshBoth(_ phone: AppSession, _ tablet: AppSession, times: Int = 4) async {
        for _ in 0..<times {
            await phone.refreshDeviceSync()
            await tablet.refreshDeviceSync()
            for _ in 0..<Gathering.yieldLimit where phone.publishing || tablet.publishing { await Task.yield() }
        }
    }

    @Test("A tablet whose disk refused its sibling's mail and then restarted still ends up with it")
    func aTabletThatRestartedStillGetsTheMail() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox(clock: clock)
        let relay = InMemoryEntrySync.Relay(announces: false, clock: clock, handsOver: .once)
        let keychain = InMemoryKeychainStore()
        let phone = TestSession.make(keychain: keychain, clock: TestClock(now: TestSession.now))
        phone.syncDevices(through: InMemoryEntrySync(relay: relay, as: "phone"))
        await phone.load()
        try await phone.createIdentity(displayName: "Bob")
        let alice = TestSession.make(clock: TestClock(now: TestSession.now))
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let room = try await phone.createRoom(named: "Kitchen")
        try await join(alice, into: room, of: phone, through: mailbox)

        let folder = TestScratch.root.appending(path: "carpenter-tablet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let log = MemoryLogStore()
        let tabletKeychain = await keychain.sibling()
        let first = tablet(log, tabletKeychain, folder, TestClock(now: TestSession.now))
        first.syncDevices(through: InMemoryEntrySync(relay: relay, as: "tablet"))
        await first.load()
        try await phone.approveNewDevice(first)
        await refreshBoth(phone, first)
        try #require(first.rooms.contains { $0.id == room }, "precondition: the tablet holds the room")
        let writer = try #require(phone.enrolment?.device.id)
        let before = first.persisted.siblingMail.cursors.first { $0.device == writer }?.mail

        await log.refuse(true)
        try await alice.send("while the tablet's disk was refusing", to: room)
        let refused = try #require(
            alice.messages(in: room).last { $0.body == "while the tablet's disk was refusing" }?.id.entry)
        try await alice.sync(through: mailbox)
        try await phone.sync(through: mailbox)
        await refreshBoth(phone, first)
        try #require(
            first.messages(in: room).contains { $0.body == "while the tablet's disk was refusing" },
            "precondition: the mail reached the tablet while its disk refused")

        await log.refuse(false)
        let reopened = tablet(log, tabletKeychain, folder, TestClock(now: TestSession.now))
        reopened.syncDevices(through: InMemoryEntrySync(relay: relay, as: "tablet"))
        await reopened.load()
        #expect(
            reopened.persisted.siblingMail.cursors.first { $0.device == writer }?.mail == before,
            "the tablet saved a cursor past mail its disk refused")
        try #require(
            !reopened.replica.allEntries.contains { $0.hash == refused },
            "precondition: the refused entry is not on disk")
        await refreshBoth(phone, reopened)
        for _ in 0..<3 {
            try await alice.sync(through: mailbox)
            try await phone.sync(through: mailbox)
            try await reopened.sync(through: mailbox)
            await refreshBoth(phone, reopened)
        }

        withKnownIssue("device sync hands a change over once, and the tablet keeps no mail it could not write") {
            #expect(
                reopened.messages(in: room).contains { $0.body == "while the tablet's disk was refusing" },
                "the reopened tablet never got the mail its disk refused")
            #expect(
                reopened.replica.allEntries.contains { $0.hash == refused },
                "the refused entry never reached the reopened tablet's log")
        }
    }
}
