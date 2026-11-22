@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
struct RoomOfThree {
    let mailbox: InMemoryMailbox
    let alice: AppSession
    let carol: AppSession
    let sam: AppSession
    let room: RoomID
    let carolKeychain: InMemoryKeychainStore
    let carolFolder: URL

    var aliceID: ParticipantID { alice.enrolment!.identity.id }
    var carolID: ParticipantID { carol.enrolment!.identity.id }
    var samID: ParticipantID { sam.enrolment!.identity.id }

    static func make(sharing clock: TestClock? = nil) async throws -> RoomOfThree {
        let mailbox = clock.map { InMemoryMailbox(clock: $0) } ?? InMemoryMailbox()
        let carolKeychain = InMemoryKeychainStore()
        let carolFolder = TestScratch.root.appending(path: "carpenter-carol-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: carolFolder, withIntermediateDirectories: true)
        let own = { clock ?? TestClock(now: TestSession.now) }
        let alice = TestSession.make(clock: own())
        let carol = TestSession.make(keychain: carolKeychain, at: carolFolder, clock: own())
        let sam = TestSession.make(clock: own())
        for (session, name) in [(alice, "Alice"), (carol, "Carol"), (sam, "Sam")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        let room = try await alice.createRoom(named: "Lanterns")
        try await join(carol, into: room, of: alice, through: mailbox)
        try await join(sam, into: room, of: alice, through: mailbox)
        let three = RoomOfThree(
            mailbox: mailbox, alice: alice, carol: carol, sam: sam, room: room, carolKeychain: carolKeychain,
            carolFolder: carolFolder)
        try await three.settle()
        try #require(alice.roster(of: room).members.count == 3, "precondition: three members")
        try #require(!carol.deviceRecipients(of: three.samID).isEmpty, "precondition: Carol can seal a key to Sam's phone")
        return three
    }

    func settle(rounds: Int = 5) async throws {
        for _ in 0..<rounds {
            for session in [alice, carol, sam] { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    func key(of session: AppSession) -> EpochNumber? {
        session.chains[room]?.highestKnownEpoch
    }
}
