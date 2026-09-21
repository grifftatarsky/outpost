import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("Who sees an Outpost", .serialized)
struct OutpostAudienceTests {
    private func acquainted() async throws -> (
        alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle([alice, bob], through: mailbox)
        return (alice, bob, mailbox)
    }

    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 5
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    @Test("Sharing a room does not hand anybody your Outpost")
    func nothingIsGrantedImplicitly() async throws {
        let (alice, bob, mailbox) = try await acquainted()
        try await alice.send("on my own wall", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        #expect(alice.outpostReaders().isEmpty)
        #expect(bob.feed().isEmpty, "a room-mate could read a wall nobody let them into")
    }

    @Test("Somebody let in can read what was already there")
    func everythingOpensTheHistory() async throws {
        let (alice, bob, mailbox) = try await acquainted()
        try await alice.send("said before you arrived", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        try await settle([alice, bob], through: mailbox)

        #expect(alice.outpostReaders() == [bobID])
        #expect(bob.feed().map(\.body).contains("said before you arrived"))
    }

    @Test("Somebody let in from now cannot read what came before")
    func fromNowSealsTheHistory() async throws {
        let (alice, bob, mailbox) = try await acquainted()
        try await alice.send("before Bob", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: false)
        try await alice.send("after Bob", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        let read = bob.feed().map(\.body)
        #expect(read.contains("after Bob"))
        #expect(!read.contains("before Bob"), "a from-now grant opened the whole history")
    }

    @Test("A later change does not take back what a from-now reader could already read")
    func aLaterChangeKeepsWhatTheyHad() async throws {
        let (alice, bob, mailbox) = try await acquainted()
        let carol = TestSession.make()
        await carol.load()
        try await carol.createIdentity(displayName: "Carol")

        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: false)
        try await alice.send("Bob can read this", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)
        #expect(bob.feed().map(\.body).contains("Bob can read this"))

        let carolID = try #require(carol.enrolment?.identity.id)
        try await alice.allowOutpost(carolID, everything: false)
        try await alice.send("and this", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        let read = bob.feed().map(\.body)
        #expect(read.contains("Bob can read this"), "an epoch change took back what he had")
        #expect(read.contains("and this"))
    }

    @Test("Somebody revoked stops reading, and keeps what they already had")
    func revocationIsForwardOnly() async throws {
        let (alice, bob, mailbox) = try await acquainted()
        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        try await alice.send("while Bob could read", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)
        #expect(bob.feed().map(\.body).contains("while Bob could read"))

        try await alice.revokeOutpost(bobID)
        try await alice.send("after Bob was shut out", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        #expect(alice.outpostReaders().isEmpty)
        let read = bob.feed().map(\.body)
        #expect(read.contains("while Bob could read"), "revocation reached backwards")
        #expect(!read.contains("after Bob was shut out"), "a revoked reader went on reading")
    }

    @Test("A photo on a wall reaches the audience, bytes and all")
    func aPhotoReachesTheAudience() async throws {
        let (alice, bob, mailbox) = try await acquainted()
        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        try await settle([alice, bob], through: mailbox)

        try await alice.post(SendingPhotoTests.photo(caption: "on the wall"), through: mailbox)
        try await settle([alice, bob], through: mailbox)

        let post = try #require(bob.feed().first)
        let media = try #require(post.media.first, "the photo did not reach the audience")
        #expect(post.body == "on the wall")
        #expect(await bob.holdsAttachment(media.id), "the entry arrived and the bytes did not")
    }

    @Test("Seeing everything includes the pictures, not only the words")
    func everythingIncludesOlderPictures() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for one in [alice, bob, carol] { await one.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")

        let room = try await alice.createRoom(named: "Lanterns")
        for joiner in [bob, carol] {
            let invite = try await alice.invite(
                joinerCode: joiner.identityCode(), joining: room, mailbox: nil)
            try await joiner.redeem(inviteCode: try invite.encoded())
            try await alice.sync(through: mailbox, media: mailbox)
            try await joiner.accept(
                invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        }
        try await settle([alice, bob, carol], through: mailbox)

        let carolID = try #require(carol.enrolment?.identity.id)
        try await alice.allowOutpost(carolID, everything: true)
        try await settle([alice, bob, carol], through: mailbox)
        try await alice.post(SendingPhotoTests.photo(caption: "posted before Bob"), through: mailbox)
        try await settle([alice, bob, carol], through: mailbox, rounds: 8)

        #expect(carol.feed().first?.media.isEmpty == false, "precondition: Carol got the picture")
        #expect(
            await mailbox.storedAttachmentCount == 0,
            "precondition: the outbox let the bytes go once its whole audience had them")
        #expect(bob.feed().isEmpty, "precondition: Bob could not read the wall at all yet")

        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        try await settle([alice, bob, carol], through: mailbox, rounds: 8)

        let post = try #require(bob.feed().first)
        #expect(post.body == "posted before Bob")
        let media = try #require(post.media.first, "the entry did not reach him")
        let bytes = try await bob.attachmentData(
            for: media, sentBy: post.author.id, through: mailbox)
        #expect(
            bytes != nil,
            "he was promised everything and given the words with a tile that never loads")
    }

    @Test("The list is folded from the log and survives a relaunch")
    func theListIsInTheLog() async throws {
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "carpenter-audience-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let alice = TestSession.make(keychain: keychain, at: directory)
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let bobID = ParticipantID(rawValue: Data(repeating: 3, count: 32))
        try await alice.allowOutpost(bobID, everything: true)
        #expect(alice.outpostAccess.grant(for: bobID)?.isAllowed == true)

        let again = TestSession.make(keychain: keychain, at: directory)
        await again.load()
        #expect(again.outpostAccess.grant(for: bobID)?.isAllowed == true)
        #expect(again.outpostReaders() == [bobID])
    }

    @Test("Nobody can be let into their own Outpost")
    func notYourself() async throws {
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let me = try #require(alice.enrolment?.identity.id)
        await #expect(throws: AppSessionError.thatIsYou) {
            try await alice.allowOutpost(me, everything: true)
        }
    }
}

actor RefusingLogStore: LogStore {
    private let real: FileLogStore
    private var appendsBeforeRefusal: Int?

    init(url: URL) { real = FileLogStore(url: url) }

    func refuseTheNextAppend() { appendsBeforeRefusal = 0 }

    func refuseAppend(afterLetting count: Int) { appendsBeforeRefusal = count }

    func append(_ entries: [Entry]) async throws {
        if let remaining = appendsBeforeRefusal {
            if remaining == 0 {
                appendsBeforeRefusal = nil
                throw CocoaError(.fileWriteNoPermission)
            }
            appendsBeforeRefusal = remaining - 1
        }
        try await real.append(entries)
    }

    func loadAll() async throws -> LoadedLog { try await real.loadAll() }
    func removeAll() async throws { try await real.removeAll() }
    func removeEntries(where shouldRemove: @escaping @Sendable (Entry) -> Bool) async throws -> Int {
        try await real.removeEntries(where: shouldRemove)
    }
}

@MainActor
@Suite("A key turn that is owed", .serialized)
struct OutpostKeyTurnTests {
    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 5
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    @Test("A revocation whose key turn fails is finished by the next round")
    func anOwedTurnIsRetried() async throws {
        let mailbox = InMemoryMailbox()
        let directory = URL.temporaryDirectory.appending(path: "carpenter-turn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = RefusingLogStore(url: directory.appending(path: "log.carpenter"))

        let alice = AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(), log: log,
                documents: FileDocumentStore(url: directory.appending(path: "state.json")),
                media: MemoryMediaStore()),
            clock: TestClock(now: TestSession.now))
        let bob = TestSession.make()
        for one in [alice, bob] { await one.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle([alice, bob], through: mailbox)

        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        try await alice.send("while Bob could read", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)
        #expect(bob.feed().map(\.body).contains("while Bob could read"))

        await log.refuseTheNextAppend()
        await #expect(throws: (any Error).self) { try await alice.revokeOutpost(bobID) }
        #expect(alice.outpostReaders().isEmpty, "the list moved him out, as it always did")
        #expect(
            alice.outpostKeyTurnPending,
            "nothing recorded that the key still has to turn, so nothing will ever turn it")

        try await settle([alice, bob], through: mailbox)
        #expect(!alice.outpostKeyTurnPending, "the turn was never retried")

        try await alice.send("after the door shut", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        let read = bob.feed().map(\.body)
        #expect(read.contains("while Bob could read"), "revocation reached backwards")
        #expect(!read.contains("after the door shut"), "a revoked reader went on reading")
    }
}

@MainActor
@Suite("Being let in later", .serialized)
struct OutpostBackfillTests {
    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    @Test("A reader let in later is handed the wall they were given the key to")
    func aLaterReaderGetsTheHistory() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for session in [alice, bob, carol] { await session.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")

        let room = try await alice.createRoom(named: "Lanterns")
        let toBob = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try toBob.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(toBob.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle([alice, bob], through: mailbox)

        try await alice.send("posted long before Carol", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        let toCarol = try await bob.invite(joinerCode: carol.identityCode(), joining: room, mailbox: nil)
        try await carol.redeem(inviteCode: try toCarol.encoded())
        try await bob.sync(through: mailbox)
        try await carol.accept(toCarol.attestation, from: try #require(bob.enrolment?.identity.publicKeys))
        try await settle([alice, bob, carol], through: mailbox)

        let carolID = try #require(carol.enrolment?.identity.id)
        #expect(
            !carol.feed().map(\.body).contains("posted long before Carol"),
            "precondition: she has no part of Alice's wall before she is let in")

        try await alice.allowOutpost(carolID, everything: true)
        try await settle([alice, bob, carol], through: mailbox)

        #expect(
            carol.feed().map(\.body).contains("posted long before Carol"),
            "she was handed the key to a wall she has none of")
    }

    @Test("Widening a from-now reader to everything actually widens it")
    func wideningAGrant() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        for session in [alice, bob] { await session.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle([alice, bob], through: mailbox)

        try await alice.send("before Bob", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: false)
        try await alice.send("after Bob", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)
        #expect(
            !bob.feed().map(\.body).contains("before Bob"),
            "precondition: a from-now grant seals what came before")

        try await alice.allowOutpost(bobID, everything: true)
        try await settle([alice, bob], through: mailbox)

        let read = bob.feed().map(\.body)
        #expect(read.contains("before Bob"), "the wider grant was never written")
        #expect(read.contains("after Bob"), "widening took back what he already had")
    }
}
