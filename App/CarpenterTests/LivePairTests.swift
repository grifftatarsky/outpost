@testable import CarpenterApp
import CarpenterCloudKit
import CarpenterKit
import CarpenterKitTesting
import CloudKit
import Foundation
import Testing

@MainActor
enum LivePair {
    static let role = ProcessInfo.processInfo.environment["CARPENTER_LIVE_PAIR_ROLE"] ?? ""
    static let run = ProcessInfo.processInfo.environment["CARPENTER_LIVE_PAIR_RUN"] ?? "none"
    static var folder: URL { URL(filePath: "/tmp/outpost-rig-exchange/live-pair/\(run)") }

    static func leave(_ value: String, as name: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try value.write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
        print("LIVE PAIR \(role): left \(name)")
    }

    static func waitFor(_ name: String, minutes: Double = 6) async throws -> String {
        let deadline = Date().addingTimeInterval(minutes * 60)
        while Date() < deadline {
            if let found = try? String(contentsOf: folder.appending(path: name), encoding: .utf8) { return found }
            try await Task.sleep(for: .seconds(2))
        }
        throw CancellationError()
    }

    static func session() -> AppSession {
        let root = URL.temporaryDirectory.appending(path: "carpenter-live-pair-\(UUID().uuidString)")
        return AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(),
                log: FileLogStore(url: root.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: root.appending(path: "state.json")),
                media: MemoryMediaStore()))
    }

    static func until(
        _ what: String, _ session: AppSession, through cloud: CloudKitMailbox, minutes: Double = 6,
        _ done: () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(minutes * 60)
        while Date() < deadline {
            try await session.sync(through: cloud, media: cloud)
            if try await done() { return }
            try await Task.sleep(for: .seconds(3))
        }
        Issue.record("\(role) waited \(minutes) minutes for \(what) and it never came")
        throw CancellationError()
    }

    static let photo = PreparedMedia(
        kind: .image, width: 1600, height: 1200, bytes: Data((0..<60_000).map { UInt8($0 % 251) }),
        preview: Data(repeating: 0xAB, count: 900), caption: nil)
}

@Suite(
    "Two people on two iCloud accounts, each writing only into spaces of their own",
    .enabled(if: LiveCloudKit.isAsked && !LivePair.role.isEmpty),
    .serialized)
@MainActor
struct LivePairTests {
    @Test(.enabled(if: LivePair.role == "alice"))
    func alice() async throws {
        let cloud = try await LiveCloudKit.mailbox()
        let alice = LivePair.session()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let room = try await alice.createRoom(named: "Lanterns")

        let code = try await LivePair.waitFor("bob-code")
        let invite = try await alice.invite(joinerCode: code, joining: room, through: cloud)
        #expect(invite.verifiedPair != nil, "the invite carried no link of Alice's")
        try LivePair.leave(try invite.encoded(), as: "alice-invite")
        let bobID = try #require(try JoinerCode.decoded(from: code).participantID as ParticipantID?)

        try await LivePair.until("Bob to join", alice, through: cloud) {
            alice.roster(of: room).members.contains(bobID)
        }
        #expect(alice.pairsJoined.contains(bobID), "Alice never joined Bob's space")

        let said = (1...24).map { "entry number \($0)" }
        for word in said { try await alice.send(word, to: room) }
        try await LivePair.until("Bob's hello", alice, through: cloud) {
            alice.messages(in: room).contains { $0.body == "hello from Bob" }
        }
        _ = try await LivePair.waitFor("bob-got-24")

        let pairs = try #require(alice.pairs())
        try await LivePair.until("Bob's receipts to empty Alice's space", alice, through: cloud) {
            try await cloud.sentPackets(in: pairs).values.filter { $0.to == bobID }.isEmpty
        }

        try await alice.send(LivePair.photo, to: room, through: cloud)
        let photo = try #require(alice.messages(in: room).last?.media?.id)
        try LivePair.leave(photo.rawValue.uuidString, as: "alice-photo")
        _ = try await LivePair.waitFor("bob-has-photo")
        try await LivePair.until("the photo's copy to be cleared once Bob had it", alice, through: cloud) {
            try await cloud.pendingAttachments(in: pairs)[photo] == nil
        }

        _ = try await LivePair.waitFor("bob-checked")
        await alice.close(pairWith: bobID, through: cloud)
        try LivePair.leave("closed", as: "alice-closed")
        _ = try await LivePair.waitFor("bob-done")
        try? await cloud.eraseEverySpace()
    }

    @Test(.enabled(if: LivePair.role == "bob"))
    func bob() async throws {
        let cloud = try await LiveCloudKit.mailbox()
        let bob = LivePair.session()
        await bob.load()
        try await bob.createIdentity(displayName: "Bob")
        let code = await bob.joinerCode(through: cloud)
        #expect(try JoinerCode.decoded(from: code).verifiedPair != nil, "Bob's code carried no link")
        try LivePair.leave(code, as: "bob-code")

        let invite = try await bob.redeem(inviteCode: try await LivePair.waitFor("alice-invite"))
        let room = invite.attestation.room
        let aliceID = invite.attestation.inviterKeys.participantID
        try await LivePair.until("to be let in", bob, through: cloud) {
            bob.roster(of: room).members.contains(bob.enrolment!.identity.id)
        }
        try await bob.send("hello from Bob", to: room)

        let said = (1...24).map { "entry number \($0)" }
        try await LivePair.until("Alice's 24 entries", bob, through: cloud) {
            bob.messages(in: room).map(\.body).filter { $0.hasPrefix("entry number") }.count == said.count
        }
        #expect(
            bob.messages(in: room).map(\.body).filter { $0.hasPrefix("entry number") } == said,
            "Alice's entries arrived out of the order she wrote them")
        try LivePair.leave("yes", as: "bob-got-24")

        let photo = AttachmentID(rawValue: try #require(UUID(uuidString: try await LivePair.waitFor("alice-photo"))))
        try await LivePair.until("Alice's photo", bob, through: cloud) { await bob.holdsAttachment(photo) }
        try LivePair.leave("yes", as: "bob-has-photo")

        let shared = CKContainer.default().sharedCloudDatabase
        let zones = try await shared.allRecordZones().map(\.zoneID).filter { $0.zoneName.hasPrefix("Pair-") }
        #expect(!zones.isEmpty, "Bob reads no space of Alice's")
        for zone in zones {
            let intruder = CKRecord(recordType: "SyncPacket", recordID: CKRecord.ID(recordName: "intruder", zoneID: zone))
            intruder["ciphertext"] = Data([1]) as NSData
            await #expect(throws: (any Error).self, "Bob wrote into Alice's space") {
                let result = try await shared.modifyRecords(saving: [intruder], deleting: [])
                _ = try result.saveResults[intruder.recordID]?.get()
            }
            let ring = try? await shared.record(for: CKRecord.ID(recordName: PairWire.ringRecord, zoneID: zone))
            #expect(ring?.recordType == PairWire.ringType, "Alice's space for Bob holds no ring")
        }
        try LivePair.leave("yes", as: "bob-checked")

        _ = try await LivePair.waitFor("alice-closed")
        let pairs = try #require(bob.pairs())
        try await LivePair.until("Alice's closed space to be gone", bob, through: cloud, minutes: 3) {
            let left = try await shared.allRecordZones().map(\.zoneID)
            let readable = await withTaskGroup(of: Bool.self) { group in
                for zone in left where zone.zoneName.hasPrefix("Pair-") {
                    group.addTask { (try? await shared.recordZone(for: zone)) != nil }
                }
                return await group.reduce(false) { $0 || $1 }
            }
            return !readable
        }
        #expect(
            try await cloud.fetch(from: aliceID, for: SyncSession.recentTags(for: bob.peers()[0], at: Date()), in: pairs)
                .isEmpty,
            "Bob still read Alice's space after she closed it")
        try LivePair.leave("done", as: "bob-done")
        try? await cloud.eraseEverySpace()
    }
}
