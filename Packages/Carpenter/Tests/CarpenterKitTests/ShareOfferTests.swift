import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Offering a mailbox back", .serialized)
@MainActor
struct ShareOfferTests {
    private func scratch() -> URL {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-offer-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func session(_ clock: TestClock) -> AppSession {
        let directory = scratch()
        return AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(),
                log: FileLogStore(url: directory.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json"))
            ),
            clock: clock
        )
    }

    private func pair(
        _ clock: TestClock, _ mailbox: InMemoryMailbox
    ) async throws -> (alice: AppSession, bob: AppSession) {
        let alice = session(clock)
        let bob = session(clock)
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
        return (alice, bob)
    }

    @Test("An offer from a peer is recognised and opened")
    func genuineOfferIsAccepted() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob) = try await pair(clock, mailbox)

        let bobsMailbox = try #require(URL(string: "https://www.icloud.com/share/bob"))
        let offers = bob.shareOffers(of: bobsMailbox)
        #expect(!offers.isEmpty, "precondition: Bob had somebody to offer to")

        let inAlicesOutbox = Dictionary(
            uniqueKeysWithValues: offers.map { ($0.name, $0.sealed) })

        let opened = alice.openShareOffers(inAlicesOutbox)
        #expect(Array(opened.values) == [bobsMailbox])
        #expect(opened.keys.first == offers.first?.name)
    }

    @Test("An offer's digest follows the URL and not the sealing")
    func digestFollowsTheURL() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (_, bob) = try await pair(clock, mailbox)

        let today = try #require(URL(string: "https://www.icloud.com/share/bob-today"))
        let tomorrow = try #require(URL(string: "https://www.icloud.com/share/bob-tomorrow"))

        let first = try #require(bob.shareOffers(of: today).first)
        let again = try #require(bob.shareOffers(of: today).first)
        let moved = try #require(bob.shareOffers(of: tomorrow).first)

        #expect(first.sealed != again.sealed, "precondition: sealing is not deterministic")
        #expect(first.digest == again.digest, "the same mailbox read as a different offer")
        #expect(first.digest != moved.digest, "a re-created mailbox read as the old one")
        #expect(first.name == moved.name, "the name is the channel, not the URL")
        #expect(!first.digest.contains("bob"), "the digest carried the URL in the clear")
    }

    @Test("An offer from a stranger is ignored")
    func strangerIsIgnored() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, _) = try await pair(clock, mailbox)

        let attackersZone = try #require(URL(string: "https://www.icloud.com/share/attacker"))

        let planted: [String: Data] = [
            "offer-0000000000000000": Data(attackersZone.absoluteString.utf8),
            "outbox-share-offer-deadbeef": Data(attackersZone.absoluteString.utf8),
            UUID().uuidString: Data(attackersZone.absoluteString.utf8),
        ]

        #expect(
            alice.openShareOffers(planted).isEmpty,
            "a zone nobody vouched for was about to be joined")
    }

    @Test("A forged body at a real offer name is ignored")
    func forgedBodyIsIgnored() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob) = try await pair(clock, mailbox)

        let genuine = try #require(URL(string: "https://www.icloud.com/share/bob"))
        let name = try #require(bob.shareOffers(of: genuine).first?.name)

        let forged = [name: Data("https://www.icloud.com/share/attacker".utf8)]
        #expect(alice.openShareOffers(forged).isEmpty, "unsealed bytes were taken at face value")
    }

    @Test("An offer reveals nothing to anybody else")
    func offerIsOpaqueToOthers() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob) = try await pair(clock, mailbox)

        let bobsMailbox = try #require(URL(string: "https://www.icloud.com/share/bob"))
        let offer = try #require(bob.shareOffers(of: bobsMailbox).first)

        let bytes = String(decoding: offer.sealed, as: UTF8.self)
        #expect(!bytes.contains("icloud.com"), "the share URL was written in the clear")
        #expect(!offer.name.contains("icloud"), "the record name leaked the URL it carries")
        _ = alice
    }
}
