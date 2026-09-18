import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("What a delivery mark is allowed to claim", .serialized)
@MainActor
struct DeliveryEvidenceTests {
    private func scratch() -> URL {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-mark-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func storage(_ directory: URL, _ keychain: InMemoryKeychainStore) -> SessionStorage {
        SessionStorage(
            keychain: keychain,
            log: FileLogStore(url: directory.appending(path: "log.carpenter")),
            documents: FileDocumentStore(url: directory.appending(path: "state.json")))
    }

    @Test("A message nobody has collected still reads as uncollected after a relaunch")
    func outstandingSurvivesARelaunch() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let directory = scratch()
        let keychain = InMemoryKeychainStore()

        let alice = AppSession(storage: storage(directory, keychain), clock: clock)
        let bob = AppSession(storage: TestSession.storage(), clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        try await alice.send("nobody has this yet", to: room)
        try await alice.sync(through: mailbox)

        let sent = alice.messages(in: room).first { $0.body == "nobody has this yet" }
        #expect(sent?.delivery == .sent, "precondition: it is in the mailbox and uncollected")

        let relaunched = AppSession(storage: storage(directory, keychain), clock: clock)
        await relaunched.load()

        let afterwards = relaunched.messages(in: room).first { $0.body == "nobody has this yet" }
        #expect(
            afterwards?.delivery.isCollected == false,
            "a relaunch forgot what was outstanding and reported an uncollected message as collected")
    }

    @Test("Collection is reported once the packet is actually gone")
    func collectionIsReportedWhenItHappens() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()

        let alice = AppSession(storage: TestSession.storage(), clock: clock)
        let bob = AppSession(storage: TestSession.storage(), clock: clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<2 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }

        try await alice.send("collect this", to: room)
        try await alice.sync(through: mailbox)
        #expect(alice.messages(in: room).first { $0.body == "collect this" }?.delivery == .sent)

        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)

        #expect(
            alice.messages(in: room).first { $0.body == "collect this" }?.delivery.isCollected
                == true,
            "the packet was acknowledged and deleted, and the mark did not follow")
    }
}
