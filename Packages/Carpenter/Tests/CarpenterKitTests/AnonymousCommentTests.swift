import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("A comment from somebody you have not met", .serialized)
struct AnonymousCommentTests {
    private func triangle(lettingAliceIn: Bool = true) async throws -> (
        alice: AppSession, bob: AppSession, carol: AppSession, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for session in [alice, bob, carol] { await session.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")

        try await introduce(bob, to: alice, named: "Lanterns", through: mailbox)
        try await introduce(bob, to: carol, named: "Kites", through: mailbox)

        let aliceID = try #require(alice.enrolment?.identity.id)
        let carolID = try #require(carol.enrolment?.identity.id)
        if lettingAliceIn { try await bob.allowOutpost(aliceID, everything: true) }
        try await bob.allowOutpost(carolID, everything: true)
        try await settle([alice, bob, carol], through: mailbox)
        return (alice, bob, carol, mailbox)
    }

    private func introduce(
        _ host: AppSession, to guest: AppSession, named name: String,
        through mailbox: InMemoryMailbox
    ) async throws {
        let room = try await host.createRoom(named: name)
        let invite = try await host.invite(joinerCode: guest.identityCode(), joining: room, mailbox: nil)
        try await guest.redeem(inviteCode: try invite.encoded())
        try await host.sync(through: mailbox)
        try await guest.accept(
            invite.attestation, from: try #require(host.enrolment?.identity.publicKeys))
        try await settle([host, guest], through: mailbox)
    }

    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    @Test("Carol's comment reaches Alice without introducing Carol")
    func theCommentTravelsAndTheNameDoesNot() async throws {
        let (alice, bob, carol, mailbox) = try await triangle()
        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        try await settle([alice, bob, carol], through: mailbox)

        let post = try #require(carol.feed().first { $0.body == "the kite is up" })
        try await carol.comment(on: post, text: "it is holding well")
        try await settle([alice, bob, carol], through: mailbox)

        let seen = try #require(alice.feed().first { $0.body == "the kite is up" })
        let comments = alice.comments(on: seen)
        #expect(comments.map(\.body) == ["it is holding well"])

        let carolID = try #require(carol.enrolment?.identity.id)
        let author = try #require(comments.first?.author)
        #expect(author.isAnonymous, "Alice was handed a person she has never met")
        #expect(author.id != carolID, "the comment still carried Carol's own address")
        #expect(author.displayName == "User 403")
        #expect(!alice.hasMet(carolID))
    }

    @Test("The people you have met are still named")
    func metPeopleAreNamed() async throws {
        let (alice, bob, carol, mailbox) = try await triangle()
        await alice.setShowsOthersNames(true)
        await bob.setSharesName(true)
        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        try await settle([alice, bob, carol], through: mailbox)

        let post = try #require(alice.feed().first { $0.body == "the kite is up" })
        #expect(!post.author.isAnonymous)
        #expect(post.author.displayName == "Bob")

        try await alice.comment(on: post, text: "from over here it looks steady")
        try await settle([alice, bob, carol], through: mailbox)
        let mine = try #require(alice.comments(on: post).first { $0.isMine })
        #expect(!mine.author.isAnonymous)
    }

    @Test("Two people you have not met are the same one person")
    func everyStrangerIsTheSameStranger() async throws {
        let (alice, bob, carol, mailbox) = try await triangle()
        let dave = TestSession.make()
        await dave.load()
        try await dave.createIdentity(displayName: "Dave")
        try await introduce(bob, to: dave, named: "Balloons", through: mailbox)
        try await bob.allowOutpost(try #require(dave.enrolment?.identity.id), everything: true)
        try await settle([alice, bob, carol, dave], through: mailbox)

        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        try await settle([alice, bob, carol, dave], through: mailbox)
        for (index, stranger) in [carol, dave].enumerated() {
            let post = try #require(stranger.feed().first { $0.body == "the kite is up" })
            try await stranger.comment(on: post, text: "seen from over here \(index)")
        }
        try await settle([alice, bob, carol, dave], through: mailbox)

        let seen = try #require(alice.feed().first { $0.body == "the kite is up" })
        let authors = alice.comments(on: seen).map(\.author)
        #expect(authors.count == 2)
        #expect(Set(authors.map(\.id)).count == 1, "the two strangers could be told apart")
        #expect(authors.allSatisfy { $0.isAnonymous })
    }

    @Test("Meeting them afterwards names what they already wrote")
    func meetingResolvesTheOldComment() async throws {
        let (alice, bob, carol, mailbox) = try await triangle()
        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        try await settle([alice, bob, carol], through: mailbox)

        let post = try #require(carol.feed().first { $0.body == "the kite is up" })
        try await carol.comment(on: post, text: "it is holding well")
        try await settle([alice, bob, carol], through: mailbox)

        let seen = try #require(alice.feed().first { $0.body == "the kite is up" })
        #expect(alice.comments(on: seen).first?.author.isAnonymous == true)

        try await introduce(carol, to: alice, named: "Ropes", through: mailbox)
        try await settle([alice, bob, carol], through: mailbox)

        let carolID = try #require(carol.enrolment?.identity.id)
        #expect(alice.hasMet(carolID))
        let named = try #require(alice.comments(on: seen).first)
        #expect(!named.author.isAnonymous)
        #expect(named.author.id == carolID)
    }

    @Test("Somebody let in afterwards gets the comments too, not only the posts")
    func aLateReaderGetsTheWholeThread() async throws {
        let (alice, bob, carol, mailbox) = try await triangle(lettingAliceIn: false)
        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        try await settle([alice, bob, carol], through: mailbox)

        let post = try #require(carol.feed().first { $0.body == "the kite is up" })
        try await carol.comment(on: post, text: "it is holding well")
        try await settle([alice, bob, carol], through: mailbox)
        #expect(alice.feed().isEmpty, "Alice was let in before the test meant her to be")

        try await bob.allowOutpost(try #require(alice.enrolment?.identity.id), everything: true)
        try await settle([alice, bob, carol], through: mailbox)

        let seen = try #require(alice.feed().first { $0.body == "the kite is up" })
        #expect(
            alice.comments(on: seen).map(\.body) == ["it is holding well"],
            "the post arrived and the thread under it did not")
    }

    @Test("A closed comment is not there at all for a co-reader who is not your reader")
    func closedIsInvisibleToTheRest() async throws {
        let (alice, bob, carol, mailbox) = try await triangle()
        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        try await settle([alice, bob, carol], through: mailbox)

        await carol.setOutpostConsent(.closed)
        try await carol.allowOutpost(try #require(bob.enrolment?.identity.id), everything: true)
        try await settle([alice, bob, carol], through: mailbox)

        let hers = try #require(carol.feed().first { $0.body == "the kite is up" })
        try await carol.comment(on: hers, text: "it is holding well")
        try await settle([alice, bob, carol], through: mailbox)

        let his = try #require(bob.feed().first { $0.body == "the kite is up" })
        #expect(bob.comments(on: his).map(\.body) == ["it is holding well"])

        let seen = try #require(alice.feed().first { $0.body == "the kite is up" })
        #expect(alice.comments(on: seen).isEmpty, "a closed comment was drawn to somebody outside it")
        #expect(seen.commentCount == 0, "a closed comment was counted to somebody outside it")
    }

    @Test("The post's owner says how many comments are missing")
    func theOwnerPublishesTheCount() async throws {
        let (alice, bob, carol, mailbox) = try await triangle()
        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        try await settle([alice, bob, carol], through: mailbox)

        await carol.setOutpostConsent(.closed)
        let hers = try #require(carol.feed().first { $0.body == "the kite is up" })
        try await carol.comment(on: hers, text: "it is holding well")
        try await settle([alice, bob, carol], through: mailbox)

        let his = try #require(bob.feed().first { $0.body == "the kite is up" })
        #expect(bob.comments(on: his).count == 1, "the owner could not read what was addressed to him")
        #expect(bob.hiddenComments(on: his) == 0, "the owner is missing nothing and should be told so")

        let seen = try #require(alice.feed().first { $0.body == "the kite is up" })
        #expect(alice.comments(on: seen).isEmpty)
        #expect(
            alice.hiddenComments(on: seen) == 1,
            "Alice was not told the thread is one comment short")
    }

    @Test("Nothing is published when nobody is closed")
    func noTallyWhenNothingIsHidden() async throws {
        let (alice, bob, carol, mailbox) = try await triangle()
        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        try await settle([alice, bob, carol], through: mailbox)

        let hers = try #require(carol.feed().first { $0.body == "the kite is up" })
        try await carol.comment(on: hers, text: "it is holding well")
        try await settle([alice, bob, carol], through: mailbox)

        let seen = try #require(alice.feed().first { $0.body == "the kite is up" })
        #expect(alice.comments(on: seen).count == 1, "an open comment should simply be readable")
        #expect(alice.hiddenComments(on: seen) == 0)
        let his = try #require(bob.feed().first { $0.body == "the kite is up" })
        #expect(
            bob.publishedTally(on: his) == nil,
            "a tally was written for a thread where everybody can count for themselves")
    }

    @Test("Somebody outside the Outpost reads none of the thread")
    func theThreadIsSealedToTheWall() async throws {
        let (alice, bob, carol, mailbox) = try await triangle()
        let erin = TestSession.make()
        await erin.load()
        try await erin.createIdentity(displayName: "Erin")
        try await introduce(bob, to: erin, named: "Ropes", through: mailbox)

        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        try await settle([alice, bob, carol, erin], through: mailbox)
        let post = try #require(carol.feed().first { $0.body == "the kite is up" })
        try await carol.comment(on: post, text: "it is holding well")
        try await settle([alice, bob, carol, erin], through: mailbox)

        #expect(erin.feed().isEmpty, "a room-mate read a wall nobody let them into")
        _ = post
    }
}

@MainActor
@Suite("Reading without joining in", .serialized)
struct OutpostConsentTests {
    private func pair() async throws -> (
        alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await bob.createRoom(named: "Lanterns")
        let invite = try await bob.invite(joinerCode: alice.identityCode(), joining: room, mailbox: nil)
        try await alice.redeem(inviteCode: try invite.encoded())
        try await bob.sync(through: mailbox)
        try await alice.accept(
            invite.attestation, from: try #require(bob.enrolment?.identity.publicKeys))
        try await bob.allowOutpost(try #require(alice.enrolment?.identity.id), everything: true)
        for _ in 0..<6 {
            for session in [alice, bob] { try await session.sync(through: mailbox, media: mailbox) }
        }
        return (alice, bob, mailbox)
    }

    @Test("Closed keeps a comment from the post's other readers")
    func closedReachesOnlyYourOwnReaders() async throws {
        let (alice, bob, mailbox) = try await pair()
        try await alice.allowOutpost(try #require(bob.enrolment?.identity.id), everything: true)
        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        await alice.setOutpostConsent(.closed)
        let post = try #require(alice.feed().first { $0.body == "the kite is up" })
        try await alice.comment(on: post, text: "steady from here")
        try await settle([alice, bob], through: mailbox)

        let his = try #require(bob.feed().first { $0.body == "the kite is up" })
        #expect(bob.comments(on: his).map(\.body) == ["steady from here"])
    }

    @Test("Closed reaches the post's author without letting them in")
    func closedReachesTheAuthorRegardless() async throws {
        let (alice, bob, mailbox) = try await pair()
        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        try await settle([alice, bob], through: mailbox)

        await alice.setOutpostConsent(.closed)
        #expect(alice.outpostReaders().isEmpty, "Alice has let nobody in, which is the point")

        let post = try #require(alice.feed().first { $0.body == "the kite is up" })
        try await alice.comment(on: post, text: "steady from here")
        try await settle([alice, bob], through: mailbox)

        let his = try #require(bob.feed().first { $0.body == "the kite is up" })
        #expect(
            bob.comments(on: his).map(\.body) == ["steady from here"],
            "the one person it was addressed to could not read it")
        #expect(
            alice.outpostReaders().isEmpty,
            "the comment let somebody into Alice's Outpost as a side effect")
    }

    @Test("Open reaches the post's readers and closed does not")
    func theTwoAnswersDiffer() async throws {
        let (alice, bob, mailbox) = try await pair()
        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        try await settle([alice, bob], through: mailbox)
        let post = try #require(alice.feed().first { $0.body == "the kite is up" })

        await alice.setOutpostConsent(.open)
        try await alice.comment(on: post, text: "open")
        try await settle([alice, bob], through: mailbox)
        let his = try #require(bob.feed().first { $0.body == "the kite is up" })
        #expect(bob.comments(on: his).map(\.body) == ["open"])
    }

    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    @Test("Read only refuses a comment on somebody else's post")
    func readOnlyRefusesTheComment() async throws {
        let (alice, bob, mailbox) = try await pair()
        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        for _ in 0..<6 {
            for session in [alice, bob] { try await session.sync(through: mailbox, media: mailbox) }
        }
        await alice.setOutpostConsent(.quiet)

        let post = try #require(alice.feed().first { $0.body == "the kite is up" })
        await #expect(throws: AppSessionError.readingOnly) {
            try await alice.comment(on: post, text: "nothing to see")
        }
        await #expect(throws: AppSessionError.readingOnly) {
            try await alice.react(to: post, emoji: "🎈")
        }
    }

    @Test("Read only leaves your own Outpost alone")
    func yourOwnPostsAreUntouched() async throws {
        let (alice, _, _) = try await pair()
        await alice.setOutpostConsent(.quiet)
        try await alice.send("on my own wall", to: try #require(alice.ownOutpost))
        let mine = try #require(alice.feed().first { $0.isMine })
        try await alice.comment(on: mine, text: "and a note under it")
        try await alice.react(to: mine, emoji: "🎈")
        #expect(alice.comments(on: mine).map(\.body) == ["and a note under it"])
    }

    @Test("Accepting lets it through again")
    func acceptingRestoresIt() async throws {
        let (alice, bob, mailbox) = try await pair()
        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        for _ in 0..<6 {
            for session in [alice, bob] { try await session.sync(through: mailbox, media: mailbox) }
        }
        await alice.setOutpostConsent(.quiet)
        await alice.setOutpostConsent(.open)

        let post = try #require(alice.feed().first { $0.body == "the kite is up" })
        try await alice.comment(on: post, text: "steady from here")
        #expect(alice.comments(on: post).map(\.body) == ["steady from here"])
    }

    @Test("Nobody is muted before they have been asked")
    func unaskedIsNotRefused() async throws {
        let (alice, bob, mailbox) = try await pair()
        try await bob.send("the kite is up", to: try #require(bob.ownOutpost))
        for _ in 0..<6 {
            for session in [alice, bob] { try await session.sync(through: mailbox, media: mailbox) }
        }
        #expect(alice.outpostConsent == nil)
        let post = try #require(alice.feed().first { $0.body == "the kite is up" })
        try await alice.comment(on: post, text: "before anybody asked")
        #expect(alice.comments(on: post).map(\.body) == ["before anybody asked"])
    }
}
