import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("The access question a room raises", .serialized)
struct OutpostReviewTests {
    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 5
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func room(
        with others: [String]
    ) async throws -> (alice: AppSession, joiners: [AppSession], room: RoomID, mailbox: InMemoryMailbox) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let room = try await alice.createRoom(named: "Zeppelin Enthusiasts")

        var joiners: [AppSession] = []
        for name in others {
            let joiner = TestSession.make()
            await joiner.load()
            try await joiner.createIdentity(displayName: name)
            let invite = try await alice.invite(
                joinerCode: joiner.identityCode(), joining: room, mailbox: nil)
            try await joiner.redeem(inviteCode: try invite.encoded())
            try await alice.sync(through: mailbox)
            try await joiner.accept(
                invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
            joiners.append(joiner)
        }
        try await settle([alice] + joiners, through: mailbox)
        return (alice, joiners, room, mailbox)
    }

    @Test("A room full of people nobody has decided about is what raises it")
    func theQuestionIsRaised() async throws {
        let (alice, joiners, room, _) = try await room(with: ["Hastur", "Camilla"])
        let review = try #require(alice.outpostReview(in: room))

        #expect(review.roomName == "Zeppelin Enthusiasts")
        #expect(review.undecided.count == 2)
        #expect(review.alreadyAllowed.isEmpty)
        #expect(review.people.count == joiners.count, "the member is not asked about themselves")
        #expect(review.isWorthAsking)
    }

    @Test("Somebody already let in is not counted, and is named as keeping it")
    func alreadyAllowedIsNotCounted() async throws {
        let (alice, joiners, room, mailbox) = try await room(with: ["Hastur", "Camilla"])
        let hastur = try #require(joiners[0].enrolment?.identity.id)
        try await alice.allowOutpost(hastur, everything: true)
        try await settle([alice] + joiners, through: mailbox)

        let review = try #require(alice.outpostReview(in: room))
        #expect(review.undecided.count == 1)
        #expect(review.alreadyAllowed.map(\.id) == [hastur])
        #expect(review.people.count == 2, "the sheet still lists everybody in the room")
    }

    @Test("Saying no is an answer, and the room stops asking")
    func refusalIsAnAnswer() async throws {
        let (alice, joiners, room, mailbox) = try await room(with: ["Hastur"])
        let hastur = try #require(joiners[0].enrolment?.identity.id)
        #expect(alice.outpostReview(in: room) != nil, "precondition: it was asking")

        try await alice.revokeOutpost(hastur, chosenIn: room)
        try await settle([alice] + joiners, through: mailbox)

        #expect(alice.outpostReview(in: room) == nil, "a refusal left the question open")
        #expect(alice.outpostReaders().isEmpty)
    }

    @Test("Saying no to somebody who was never let in does not turn the wall's key")
    func refusingCostsNoKeyTurn() async throws {
        let (alice, joiners, _, mailbox) = try await room(with: ["Hastur", "Camilla"])
        try await alice.send("before any of it", to: nil)
        try await settle([alice] + joiners, through: mailbox)

        let camilla = try #require(joiners[1].enrolment?.identity.id)
        try await alice.allowOutpost(camilla, everything: true)
        try await settle([alice] + joiners, through: mailbox)
        #expect(joiners[1].feed().map(\.body).contains("before any of it"))

        let before = alice.entryCount
        try await alice.revokeOutpost(try #require(joiners[0].enrolment?.identity.id))
        #expect(
            alice.entryCount == before + 1,
            "the wall's key turned to shut out somebody who was never let in")

        let quiet = alice.entryCount
        try await alice.revokeOutpost(camilla)
        #expect(
            alice.entryCount == quiet + 2,
            "the key did not turn for a reader who actually held it")
    }

    @Test("Later silences the room about the people it was asked about")
    func laterIsAboutThesePeople() async throws {
        let (alice, _, room, _) = try await room(with: ["Hastur", "Camilla"])
        #expect(alice.outpostReview(in: room) != nil)

        await alice.postponeOutpostReview(in: room)
        #expect(alice.outpostReview(in: room) == nil, "Later did not quieten it")
    }

    @Test("Somebody who joins after Later brings the question back")
    func aNewArrivalRaisesItAgain() async throws {
        let (alice, joiners, room, mailbox) = try await room(with: ["Hastur"])
        await alice.postponeOutpostReview(in: room)
        #expect(alice.outpostReview(in: room) == nil, "precondition: it was put off")

        let camilla = TestSession.make()
        await camilla.load()
        try await camilla.createIdentity(displayName: "Camilla")
        let invite = try await alice.invite(
            joinerCode: camilla.identityCode(), joining: room, mailbox: nil)
        try await camilla.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await camilla.accept(
            invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle([alice, camilla] + joiners, through: mailbox)

        let review = try #require(
            alice.outpostReview(in: room), "a person nobody had decided about was never raised")
        #expect(review.undecided.count == 2)
    }

    @Test("An answer remembers which room's review it was given in")
    func theRoomIsRemembered() async throws {
        let (alice, joiners, room, mailbox) = try await room(with: ["Hastur", "Camilla"])
        let hastur = try #require(joiners[0].enrolment?.identity.id)
        try await alice.allowOutpost(hastur, everything: true, chosenIn: room)
        try await settle([alice] + joiners, through: mailbox)

        let review = try #require(alice.outpostReview(in: room))
        let named = try #require(review.people.first { $0.id == hastur })
        #expect(named.decidedIn == "Zeppelin Enthusiasts")
        #expect(named.grant?.chosenIn == room)

        let camilla = try #require(joiners[1].enrolment?.identity.id)
        try await alice.allowOutpost(camilla, everything: false)
        try await settle([alice] + joiners, through: mailbox)
        #expect(alice.outpostReview(in: room) == nil, "precondition: everybody now has an answer")
        #expect(alice.outpostAccess.grant(for: camilla)?.chosenIn == nil)
    }

    @Test("A room this member has left raises nothing")
    func aRoomYouAreOutOfAsksNothing() async throws {
        let (alice, joiners, room, mailbox) = try await room(with: ["Hastur"])
        #expect(alice.outpostReview(in: room) != nil, "precondition: it was asking")

        try await alice.leave(room)
        try await settle([alice] + joiners, through: mailbox)

        #expect(alice.outpostReview(in: room) == nil)
    }
}

@Suite("What a review row knows")
struct OutpostReviewRowTests {
    private func person(_ name: String, _ seed: UInt8) -> Member {
        Member(id: ParticipantID(rawValue: Data(repeating: seed, count: 32)), displayName: name)
    }

    @Test("The people with no answer come first, then the rest by name")
    func undecidedFirst() {
        let review = OutpostReview(
            room: RoomID(), roomName: "Zeppelin Enthusiasts",
            people: [
                OutpostReview.Person(member: person("Camilla", 1), grant: OutpostAccess.Grant()),
                OutpostReview.Person(member: person("Yhtill", 2), grant: nil),
                OutpostReview.Person(member: person("Hastur", 3), grant: nil),
            ])

        #expect(review.people.map(\.member.displayName) == ["Hastur", "Yhtill", "Camilla"])
        #expect(review.undecided.count == 2)
        #expect(review.alreadyAllowed.map(\.member.displayName) == ["Camilla"])
    }

    @Test("A refusal is an answer that grants nothing")
    func refusalIsNeither() {
        let refused = OutpostReview.Person(
            member: person("Thale", 4),
            grant: OutpostAccess.Grant(isAllowed: false))

        #expect(!refused.isUndecided, "a refusal read as a question nobody had answered")
        #expect(!refused.isAllowed)
    }

    @Test("A room where everybody has an answer asks nothing")
    func nothingToAsk() {
        let review = OutpostReview(
            room: RoomID(), roomName: "Lanterns",
            people: [
                OutpostReview.Person(member: person("Camilla", 1), grant: OutpostAccess.Grant()),
                OutpostReview.Person(
                    member: person("Thale", 2), grant: OutpostAccess.Grant(isAllowed: false)),
            ])
        #expect(!review.isWorthAsking)
    }
}
