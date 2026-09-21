import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterUI

@MainActor
@Suite("What is new on a wall", .serialized)
struct OutpostUnseenTests {
    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func acquainted(
        _ clock: TestClock
    ) async throws -> (alice: AppSession, bob: AppSession, InMemoryMailbox) {
        let mailbox = InMemoryMailbox()
        let alice = AppSession(storage: TestSession.storage(), clock: clock)
        let bob = AppSession(storage: TestSession.storage(), clock: clock)
        for one in [alice, bob] { await one.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(
            invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle([alice, bob], through: mailbox)
        return (alice, bob, mailbox)
    }

    @Test("A wall handed over in one round is not handed over as unread")
    func theBackCatalogueIsNotNews() async throws {
        let clock = TestClock(now: TestSession.now)
        let (alice, bob, mailbox) = try await acquainted(clock)
        let bobID = try #require(bob.enrolment?.identity.id)
        let aliceID = try #require(alice.enrolment?.identity.id)

        for word in ["one", "two", "three"] {
            try await alice.send(word, to: try #require(alice.ownOutpost))
            clock.advance(by: 60)
        }
        try await alice.allowOutpost(bobID, everything: true)
        try await settle([alice, bob], through: mailbox)

        #expect(bob.feed().count == 3, "precondition: he was handed the whole wall")
        #expect(bob.unseenPosts(from: aliceID) == 0, "a back catalogue arrived as three unread")
        #expect(bob.outpostAuthorsWithUnseen().isEmpty)
    }

    @Test("A post after that is new, and opening the wall clears it")
    func whatComesAfterIsNew() async throws {
        let clock = TestClock(now: TestSession.now)
        let (alice, bob, mailbox) = try await acquainted(clock)
        let bobID = try #require(bob.enrolment?.identity.id)
        let aliceID = try #require(alice.enrolment?.identity.id)

        try await alice.allowOutpost(bobID, everything: true)
        try await settle([alice, bob], through: mailbox)

        clock.advance(by: 60)
        try await alice.send("said after he arrived", to: try #require(alice.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        #expect(bob.unseenPosts(from: aliceID) == 1)
        #expect(bob.outpostAuthorsWithUnseen() == [aliceID])

        await bob.markOutpostSeen(from: aliceID)
        #expect(bob.unseenPosts(from: aliceID) == 0, "opening the wall did not clear it")
        #expect(bob.outpostAuthorsWithUnseen().isEmpty)
    }

    @Test("Your own posts are never new to you")
    func yourOwnIsNeverNew() async throws {
        let clock = TestClock(now: TestSession.now)
        let (alice, _, _) = try await acquainted(clock)
        let aliceID = try #require(alice.enrolment?.identity.id)

        try await alice.send("mine", to: try #require(alice.ownOutpost))
        #expect(alice.unseenPosts(from: aliceID) == 0)
        #expect(alice.outpostAuthorsWithUnseen().isEmpty)
    }

    @Test("Reading one wall does not clear another")
    func marksArePerAuthor() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let alice = AppSession(storage: TestSession.storage(), clock: clock)
        let bob = AppSession(storage: TestSession.storage(), clock: clock)
        let carol = AppSession(storage: TestSession.storage(), clock: clock)
        for one in [alice, bob, carol] { await one.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")

        let room = try await alice.createRoom(named: "Lanterns")
        for joiner in [bob, carol] {
            let invite = try await alice.invite(
                joinerCode: joiner.identityCode(), joining: room, mailbox: nil)
            try await joiner.redeem(inviteCode: try invite.encoded())
            try await alice.sync(through: mailbox)
            try await joiner.accept(
                invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        }
        try await settle([alice, bob, carol], through: mailbox)

        let bobID = try #require(bob.enrolment?.identity.id)
        let aliceID = try #require(alice.enrolment?.identity.id)
        let carolID = try #require(carol.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        try await carol.allowOutpost(bobID, everything: true)
        try await settle([alice, bob, carol], through: mailbox)

        clock.advance(by: 60)
        try await alice.send("from Alice", to: try #require(alice.ownOutpost))
        try await carol.send("from Carol", to: try #require(carol.ownOutpost))
        try await settle([alice, bob, carol], through: mailbox)
        #expect(bob.outpostAuthorsWithUnseen() == [aliceID, carolID])

        await bob.markOutpostSeen(from: aliceID)
        #expect(
            bob.outpostAuthorsWithUnseen() == [carolID],
            "reading one wall cleared the ring on another")
    }
}

@MainActor
@Suite("Asking to be told about somebody's posts", .serialized)
struct OutpostNotifyTests {
    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func pair(
        _ clock: TestClock
    ) async throws -> (alice: AppSession, bob: AppSession, InMemoryMailbox) {
        let mailbox = InMemoryMailbox()
        let alice = AppSession(storage: TestSession.storage(), clock: clock)
        let bob = AppSession(storage: TestSession.storage(), clock: clock)
        for one in [alice, bob] { await one.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(
            invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle([alice, bob], through: mailbox)
        let bobID = try #require(bob.enrolment?.identity.id)
        try await alice.allowOutpost(bobID, everything: true)
        try await settle([alice, bob], through: mailbox)
        return (alice, bob, mailbox)
    }

    @Test("Asking to be told reaches the person whose wall it is")
    func theWishTravels() async throws {
        let clock = TestClock(now: TestSession.now)
        let (alice, bob, mailbox) = try await pair(clock)
        let aliceID = try #require(alice.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)

        #expect(!alice.wantsOutpostBellFrom(bobID), "precondition: nobody has asked")

        await bob.setNotified(true, about: aliceID)
        try await settle([alice, bob], through: mailbox)

        #expect(bob.isNotified(about: aliceID))
        #expect(alice.wantsOutpostBellFrom(bobID), "the wish never reached the wall's owner")
    }

    @Test("Stopping travels too")
    func stoppingTravels() async throws {
        let clock = TestClock(now: TestSession.now)
        let (alice, bob, mailbox) = try await pair(clock)
        let aliceID = try #require(alice.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)

        await bob.setNotified(true, about: aliceID)
        try await settle([alice, bob], through: mailbox)
        #expect(alice.wantsOutpostBellFrom(bobID), "precondition: he had asked")

        await bob.setNotified(false, about: aliceID)
        try await settle([alice, bob], through: mailbox)
        #expect(!alice.wantsOutpostBellFrom(bobID), "he stopped asking and was still on the list")
    }

    @Test("A post rings the readers who asked, and no one else")
    func onlyThoseWhoAskedAreRung() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let alice = AppSession(storage: TestSession.storage(), clock: clock)
        let bob = AppSession(storage: TestSession.storage(), clock: clock)
        let carol = AppSession(storage: TestSession.storage(), clock: clock)
        for one in [alice, bob, carol] { await one.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")

        let room = try await alice.createRoom(named: "Lanterns")
        for joiner in [bob, carol] {
            let invite = try await alice.invite(
                joinerCode: joiner.identityCode(), joining: room, mailbox: nil)
            try await joiner.redeem(inviteCode: try invite.encoded())
            try await alice.sync(through: mailbox)
            try await joiner.accept(
                invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        }
        try await settle([alice, bob, carol], through: mailbox)

        let aliceID = try #require(alice.enrolment?.identity.id)
        for one in [bob, carol] {
            try await alice.allowOutpost(
                try #require(one.enrolment?.identity.id), everything: true)
        }
        try await settle([alice, bob, carol], through: mailbox)

        await bob.setNotified(true, about: aliceID)
        try await settle([alice, bob, carol], through: mailbox)

        clock.advance(by: 60)
        let before = await mailbox.bells.count
        try await alice.send("worth telling one of them about", to: try #require(alice.ownOutpost))
        try await alice.sync(through: mailbox, media: mailbox)

        let rung = await mailbox.bells.dropFirst(before)
        #expect(rung.count == 1, "a wall post rang \(rung.count) people rather than the one who asked")
    }

    @Test("The wish survives a relaunch")
    func survivesARelaunch() async throws {
        let clock = TestClock(now: TestSession.now)
        let keychain = InMemoryKeychainStore()
        let directory = URL.temporaryDirectory.appending(path: "carpenter-bell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let bob = TestSession.make(keychain: keychain, at: directory)
        await bob.load()
        try await bob.createIdentity(displayName: "Bob")
        let alice = ParticipantID(rawValue: Data(repeating: 4, count: 32))
        await bob.setNotified(true, about: alice)

        let again = TestSession.make(keychain: keychain, at: directory)
        await again.load()
        #expect(again.isNotified(about: alice))
        _ = clock
    }
}

@Suite("The index a name files under")
struct OutpostListIndexTests {
    @Test("A letter files under its own capital")
    func letters() {
        #expect(OutpostListView.index(of: "camilla") == "C")
        #expect(OutpostListView.index(of: "Hastur") == "H")
        #expect(OutpostListView.index(of: "  Yhtill") == "Y")
    }

    @Test("Anything that is not a letter files under a hash")
    func others() {
        #expect(OutpostListView.index(of: "42") == "#")
        #expect(OutpostListView.index(of: "") == "#")
        #expect(OutpostListView.index(of: "…quiet") == "#")
    }
}

@Suite("What a post's banner says")
struct PostNotificationCopyTests {
    private let camilla = ParticipantID(rawValue: Data(repeating: 5, count: 32))

    @Test("At the loudest rung it names them, says what happened, and shows the words")
    func everything() {
        let copy = MessageNotification.ofPost(
            author: camilla, name: "Camilla", body: "the mast is staying", level: .everything)
        #expect(copy.title == "Camilla")
        #expect(copy.subtitle.contains("Posted"))
        #expect(copy.body == "the mast is staying")
        #expect(!copy.isGeneric)
    }

    @Test("A post never reads as a message from the same person")
    func notMistakableForAMessage() {
        let post = MessageNotification.ofPost(
            author: camilla, name: "Camilla", body: "hello", level: .everything)
        let message = MessageNotification.of(
            room: ConversationID.room(UUID()), roomName: "", author: "Camilla", body: "hello", level: .everything)
        #expect(post != message)
    }

    @Test("The quietest rung says nothing at all")
    func nothing() {
        #expect(
            MessageNotification.ofPost(
                author: camilla, name: "Camilla", body: "hello", level: .nothing
            ).isGeneric)
    }

    @Test("A wall's posts group as one thread, and never with a room's")
    func grouping() {
        let mine = MessageNotification.ofPost(
            author: camilla, name: "Camilla", body: "one", level: .everything)
        let also = MessageNotification.ofPost(
            author: camilla, name: "Camilla", body: "two", level: .everything)
        #expect(mine.threadID == also.threadID)
        #expect(mine.threadID != MessageNotification.thread(for: ConversationID.room(UUID())))
        #expect(!mine.threadID.isEmpty)
    }

    @Test("A post from nobody nameable is the generic banner")
    func nameless() {
        #expect(
            MessageNotification.ofPost(
                author: camilla, name: "   ", body: "hello", level: .everything
            ).isGeneric)
    }
}
