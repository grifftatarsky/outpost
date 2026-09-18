import CarpenterKit
import CloudKit
import Foundation
import Testing

@testable import CarpenterCloudKit

private final class FixedClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date

    init(_ now: Date) { instant = now }

    var now: Date { lock.withLock { instant } }

    func advance(by interval: TimeInterval) {
        lock.withLock { instant.addTimeInterval(interval) }
    }
}

@Suite("Which zone answers to which address", .serialized)
struct PeerZoneDirectoryTests {
    private static func tag(_ seed: UInt8) -> RecipientTag {
        RecipientTag(rawValue: Data(repeating: seed, count: 32))
    }

    private static func zone(_ owner: String) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: CloudKitMailbox.outboxZoneName, ownerName: owner)
    }

    private static func store() -> FileDocumentStore {
        FileDocumentStore(
            url: URL.temporaryDirectory.appending(path: "directory-\(UUID().uuidString).json"))
    }

    @Test("A learned address answers with the zone it was learned from")
    func aLearnedAddressAnswers() async {
        let directory = PeerZoneDirectory()
        let mine = Self.tag(1)

        await directory.learn(zone: Self.zone("_peer"), in: .shared, for: [mine])

        let found = await directory.place(for: mine)
        #expect(found?.0.ownerName == "_peer")
        #expect(found?.1 == .shared)
        #expect(
            await directory.place(for: Self.tag(2)) == nil,
            """
            An address nobody has written to us under resolved to a zone anyway. `offer()` places \
            our share URL in whatever `place(for:)` returns, and a wrong answer leaves the offer \
            sealed to one peer in another peer's zone, where the peer it was for never looks.
            """)
    }

    @Test("A learned address survives being put down and picked up again")
    func aLearnedAddressSurvivesARestart() async {
        let store = Self.store()
        let mine = Self.tag(3)

        let first = PeerZoneDirectory(store: store)
        await first.learn(zone: Self.zone("_peer"), in: .shared, for: [mine])

        let second = PeerZoneDirectory(store: store)
        await second.restore()

        let found = await second.place(for: mine)
        #expect(
            found?.0.ownerName == "_peer" && found?.1 == .shared,
            """
            A learned address did not survive a relaunch, so every peer becomes unreachable until \
            they write to us again — and the reverse channel's whole job is to stop that being the \
            only way through.
            """)
    }

    @Test("Today's and tomorrow's addresses can be learned together")
    func rotationLearnsEveryWindow() async {
        let directory = PeerZoneDirectory()
        let yesterday = Self.tag(4)
        let today = Self.tag(5)
        let tomorrow = Self.tag(6)

        await directory.learn(
            zone: Self.zone("_peer"), in: .shared, for: [yesterday, today, tomorrow])

        for tag in [yesterday, today, tomorrow] {
            #expect(
                await directory.place(for: tag)?.0.ownerName == "_peer",
                """
                One of the peer's recent addresses did not resolve. Tags rotate by window, and \
                `SyncSession.recentTags` hands the mailbox every recent one precisely so a place \
                learned under today's answers for tomorrow's. If only one sticks, the reverse \
                channel goes dark at whatever hour the window turns.
                """)
        }
        #expect(await directory.learnedCount == 3)
    }

    @Test("An address older than the lifetime is dropped when it is picked up")
    func aStaleAddressIsDroppedOnRestore() async {
        let store = Self.store()
        let clock = FixedClock(Date(timeIntervalSince1970: 1_000_000))
        let mine = Self.tag(7)

        let first = PeerZoneDirectory(store: store, clock: clock)
        await first.learn(zone: Self.zone("_peer"), in: .shared, for: [mine])

        let later = FixedClock(clock.now.addingTimeInterval(PeerZoneDirectory.lifetime + 1))
        let second = PeerZoneDirectory(store: store, clock: later)
        await second.restore()

        #expect(
            await second.place(for: mine) == nil,
            """
            An address older than the thirty-day lifetime came back. It is kept for that long \
            because a peer's zone does not move, and dropped after because a tag from a month ago \
            is not an address any more — keeping it means writing an offer nobody will read.
            """)
        #expect(await second.learnedCount == 0)
    }

    @Test("A stale address is dropped the next time anything is learned")
    func aStaleAddressIsDroppedOnTheNextWrite() async {
        let store = Self.store()
        let clock = FixedClock(Date(timeIntervalSince1970: 1_000_000))
        let directory = PeerZoneDirectory(store: store, clock: clock)
        let old = Self.tag(8)
        let fresh = Self.tag(9)

        await directory.learn(zone: Self.zone("_old"), in: .shared, for: [old])
        clock.advance(by: PeerZoneDirectory.lifetime + 1)
        await directory.learn(zone: Self.zone("_new"), in: .shared, for: [fresh])

        #expect(
            await directory.place(for: old) == nil,
            """
            The save kept an address past its lifetime, so the file grows with every peer this \
            device has ever heard from and `place(for:)` keeps answering for zones that stopped \
            being anybody's address a month ago.
            """)
        #expect(await directory.place(for: fresh)?.0.ownerName == "_new")
        #expect(await directory.learnedCount == 1)
    }

    @Test("A directory with nowhere to write still answers in memory")
    func noStoreStillWorks() async {
        let directory = PeerZoneDirectory()
        let mine = Self.tag(10)

        await directory.learn(zone: Self.zone("_peer"), in: .private, for: [mine])
        await directory.restore()

        #expect(
            await directory.place(for: mine)?.1 == .private,
            """
            `restore()` on a directory with no store wiped what was learned this launch. The \
            mailbox constructs one without a store by default, and the app calls `restoreDirectory` \
            on every bring-up.
            """)
    }
}
