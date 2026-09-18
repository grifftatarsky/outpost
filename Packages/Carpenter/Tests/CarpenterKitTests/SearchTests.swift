import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("Searching what was said", .serialized)
struct SearchTests {
    private func pair(named name: String = "Lanterns") async throws -> (
        mine: AppSession, theirs: AppSession, room: RoomID, mailbox: InMemoryMailbox
    ) {
        let (mine, theirs, room, mailbox, _) = try await pairWithClock(named: name)
        return (mine, theirs, room, mailbox)
    }

    private func pairWithClock(named name: String = "Lanterns") async throws -> (
        mine: AppSession, theirs: AppSession, room: RoomID, mailbox: InMemoryMailbox,
        clock: TestClock
    ) {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let mine = TestSession.make(clock: clock)
        let theirs = TestSession.make(clock: clock)
        for session in [mine, theirs] { await session.load() }
        try await mine.createIdentity(displayName: "Griff")
        try await theirs.createIdentity(displayName: "Outie")

        let room = try await mine.createRoom(named: name)
        let invite = try await mine.invite(
            joinerCode: theirs.identityCode(), joining: room, mailbox: nil)
        try await theirs.redeem(inviteCode: try invite.encoded())
        try await mine.sync(through: mailbox)
        try await theirs.accept(
            invite.attestation, from: try #require(mine.enrolment?.identity.publicKeys))
        try await settle([mine, theirs], through: mailbox)
        return (mine, theirs, room, mailbox, clock)
    }

    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    // MARK: What it finds

    @Test("A search shorter than two characters returns nothing at all")
    func aSearchShorterThanTwoCharactersReturnsNothing() async throws {
        let (mine, _, room, _) = try await pair()
        try await mine.send("a", to: room)

        #expect(mine.search("").isEmpty)
        #expect(mine.search("a").isEmpty, "one character matches most of a transcript")
        #expect(
            mine.search(" a ").isEmpty,
            "the query is trimmed before it is measured, or a space would buy a match")
    }

    @Test("It finds a conversation by name")
    func itFindsAConversationByName() async throws {
        let (mine, _, room, _) = try await pair(named: "Kitchen")
        let found = mine.search("kitch")
        #expect(found.conversations.map(\.room) == [room], "a room was not found by its own name")
        #expect(
            found.conversations.first?.name == "Kitchen",
            "the row carries the name the member would recognise")
    }

    @Test("It finds what somebody said, and says where")
    func itFindsWhatSomebodySaidAndSaysWhere() async throws {
        let (mine, _, room, _) = try await pair(named: "Kitchen")
        try await mine.send("the tap is dripping again", to: room)
        try await mine.send("nothing to do with taps", to: room)

        let found = mine.search("dripping")
        #expect(found.said.count == 1, "a search matched more than the line that contains it")
        #expect(found.said.first?.body == "the tap is dripping again")
        #expect(
            found.said.first?.roomName == "Kitchen",
            "a result that cannot say which room it came from is not usable")
    }

    @Test("It finds what the other person said, not only your own")
    func itFindsWhatTheOtherPersonSaid() async throws {
        let (mine, theirs, room, mailbox) = try await pair()
        try await theirs.send("I put the kettle on", to: room)
        try await settle([mine, theirs], through: mailbox)

        let found = mine.search("kettle")
        #expect(found.said.count == 1, "search only looked at this member's own messages")
        #expect(
            found.said.first?.author.id == theirs.enrolment?.identity.id,
            "the result is attributed to the wrong person")
        #expect(
            found.said.first?.author.displayName != "Griff",
            """
            Somebody else's message came back attributed to this member. A name is only drawn when             the other person shares one, which is off by default — so a short code here is right             and this member's own name would not be.
            """)
    }

    @Test("A match is found however it was capitalised")
    func aMatchIsFoundHoweverItWasCapitalised() async throws {
        let (mine, _, room, _) = try await pair()
        try await mine.send("The Goodyear Blimp", to: room)
        #expect(!mine.search("goodyear").said.isEmpty, "search is case-sensitive")
        #expect(!mine.search("GOODYEAR").said.isEmpty)
    }

    @Test("Results come back newest first")
    func resultsComeBackNewestFirst() async throws {
        let (mine, _, room, _, clock) = try await pairWithClock()
        for body in ["taps one", "taps two", "taps three"] {
            try await mine.send(body, to: room)
            clock.advance(by: 60)
        }

        let bodies = mine.search("taps").said.map(\.body)
        #expect(
            bodies == ["taps three", "taps two", "taps one"],
            "a search that does not put the most recent first is a search people scroll")
    }

    @Test("Messages written in the same instant keep the order they were written in")
    func messagesInTheSameInstantKeepTheirOrder() async throws {
        let (mine, _, room, _) = try await pair()
        for body in ["taps one", "taps two", "taps three"] {
            try await mine.send(body, to: room)
        }

        #expect(
            mine.search("taps").said.map(\.body) == ["taps one", "taps two", "taps three"],
            """
            The sort is on wall time alone, so messages sharing an instant fall back on the order             the log holds them in. That is the honest answer and it is worth pinning: a search             whose order changed between runs would read as messages moving.
            """)
    }

    @Test("A post is found on its words and on who wrote it")
    func aPostIsFoundOnItsWordsAndOnWhoWroteIt() async throws {
        let (mine, _, _, _) = try await pair()
        try await mine.send("ice plants in bloom along the path", to: nil)

        #expect(!mine.search("ice plants").posts.isEmpty, "a post was not searched")
        #expect(!mine.search("Griff").posts.isEmpty, "a post was not found by its author")
    }

    // MARK: What it refuses to find

    @Test("A withdrawn message is not findable")
    func aWithdrawnMessageIsNotFindable() async throws {
        let (mine, _, room, _) = try await pair()
        try await mine.send("said in error", to: room)
        let message = try #require(mine.messages(in: room).first { $0.body == "said in error" })
        try await mine.withdraw(message.id)

        #expect(
            mine.search("said in error").said.isEmpty,
            "a message taken back came back through search")
    }

    @Test("A hidden message is not findable")
    func aHiddenMessageIsNotFindable() async throws {
        let (mine, theirs, room, mailbox) = try await pair()
        try await theirs.send("something I would rather not see", to: room)
        try await settle([mine, theirs], through: mailbox)

        let message = try #require(mine.messages(in: room).first { $0.body.contains("rather not") })
        await mine.hide(message.id)

        #expect(
            mine.search("rather not").said.isEmpty,
            """
            A message this member hid was handed back by search. Hiding is the one control that \
            promises somebody will not see a thing again.
            """)
    }

    @Test("A blocked person's messages are not findable")
    func aBlockedPersonsMessagesAreNotFindable() async throws {
        let (mine, theirs, room, mailbox) = try await pair()
        try await theirs.send("from somebody you blocked", to: room)
        try await settle([mine, theirs], through: mailbox)
        #expect(!mine.search("blocked").said.isEmpty, "the fixture never arrived")

        await mine.block(try #require(theirs.enrolment?.identity.id))

        #expect(
            mine.search("blocked").said.isEmpty,
            "blocking hid a person from the transcript and not from search")
    }

    @Test("A blocked person's posts are not findable, and leave the feed")
    func aBlockedPersonsPostsAreNotFindable() async throws {
        let (mine, theirs, _, mailbox) = try await pair()
        let mineID = try #require(mine.enrolment?.identity.id)
        let theirsID = try #require(theirs.enrolment?.identity.id)
        try await theirs.allowOutpost(mineID, everything: true)
        try await settle([mine, theirs], through: mailbox)
        try await theirs.send("a wall post from somebody you will block", to: nil)
        try await settle([mine, theirs], through: mailbox)

        #expect(!mine.feed().isEmpty, "the fixture never arrived")
        #expect(!mine.search("wall post").posts.isEmpty, "the fixture is not searchable")

        await mine.block(theirsID)

        #expect(
            mine.search("wall post").posts.isEmpty,
            """
            A blocked person's post came back through search. `block` only ever filtered messages, \
            because `feed()` was the raw projection — found 2026-09-13.
            """)
        #expect(
            mine.feed().allSatisfy { $0.author.id != theirsID },
            "a blocked person's posts are still drawn on the Outposts tab")
        #expect(
            mine.outpostAuthors().allSatisfy { $0.id != theirsID },
            "a blocked person's wall is still offered on the rail")
        #expect(
            !mine.outpostAuthorsWithUnseen().contains(theirsID),
            "a blocked person's wall still counts towards the Outposts badge")
    }
}
