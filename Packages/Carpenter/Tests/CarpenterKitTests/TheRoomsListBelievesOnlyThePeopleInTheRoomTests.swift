@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("The rooms list believes only the people in the room", .serialized)
struct TheRoomsListBelievesOnlyThePeopleInTheRoomTests {
    private func samRemoved() async throws -> RoomOfThree {
        let t = try await RoomOfThree.make()
        try await t.carol.send("before Sam went", to: t.room)
        try await t.settle()
        try await t.alice.remove(t.samID, from: t.room)
        try await t.settle()
        try #require(t.alice.roster(of: t.room).removal(of: t.samID) != nil, "precondition: Sam is out")
        return t
    }

    private func samWritesAnyway(_ payload: Payload, in t: RoomOfThree) throws {
        let sam = try #require(t.sam.enrolment)
        let chain = try #require(t.sam.chains[t.room])
        let entry = try Entry.append(
            after: t.sam.head, author: sam.identity.id, device: sam.device, clock: t.sam.replica.frontier,
            wallTime: TestSession.now.addingTimeInterval(86_400), room: t.room, payload: payload,
            at: try #require(chain.highestKnownEpoch), sealedWith: chain,
            roomLink: RoomLink(previous: t.sam.roomHeads[t.room]?.hash))
        _ = try t.alice.replica.integrate(entry)
        t.alice.refresh()
    }

    @Test("What a removed member writes afterwards is not the room's preview, its latest activity or a recent speaker")
    func aRemovedMembersPostIsNotThePreview() async throws {
        let t = try await samRemoved()
        let before = try #require(t.alice.rooms.first { $0.id == t.room })

        try samWritesAnyway(try Payload.post("still here"), in: t)

        let row = try #require(t.alice.rooms.first { $0.id == t.room })
        #expect(row.lastMessage != "still here", "the rooms list showed what Sam wrote after his removal")
        #expect(row.lastAuthor?.id != t.samID)
        #expect(row.lastActivity == before.lastActivity, "Sam moved the room's latest activity after his removal")
        #expect(!row.recentSpeakers.contains { $0.id == t.samID }, "Sam said nothing while he was in, and was listed as a recent speaker")
        #expect(t.alice.latestIncomingMessage()?.body != "still here", "a notification would have shown Sam's words")
    }

    @Test("A removed member cannot rename the room")
    func aRemovedMemberCannotRename() async throws {
        let t = try await samRemoved()

        try samWritesAnyway(try Payload.roomProfile(name: "Sam's room"), in: t)

        #expect(t.alice.rooms.first { $0.id == t.room }?.name == "Lanterns", "Sam renamed the room after his removal")
        #expect(t.alice.roster(of: t.room).name == "Lanterns")
    }
}

@Suite("A room is named only by somebody in it")
struct ARoomIsNamedOnlyBySomebodyInItTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func write(_ author: Identity, _ body: Payload, hash: UInt8, to roster: inout RoomRoster) {
        roster.apply(
            RenderedEntry(
                id: EntryHash(rawValue: Data(repeating: hash, count: 32)), type: body.type, author: author.id,
                device: DeviceID(rawValue: WideID.of([])), wallTime: start, room: roster.room,
                content: .text(""), editedAt: nil, replyingTo: nil, reactions: [:]),
            body: body)
    }

    @Test("A profile from somebody who is not in the room does not rename it, and one from a member does")
    func onlyAMemberRenames() throws {
        let (alice, bob, stranger) = (Identity.generate(), Identity.generate(), Identity.generate())
        let (room, profile) = try TestFounding.room(named: "Hangar 7", by: alice.id)
        var roster = RoomRoster(room: room)
        write(alice, profile, hash: 1, to: &roster)

        write(stranger, try Payload.roomProfile(name: "The stranger's"), hash: 2, to: &roster)
        #expect(roster.name == "Hangar 7", "somebody who was never in the room renamed it")

        let invite = try TestInvite.issue(joining: room, joinerKeys: bob.publicKeys, by: alice, at: start)
        write(alice, try Payload.joinRequest(invite), hash: 3, to: &roster)
        write(alice, try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: bob)), hash: 4, to: &roster)
        write(bob, try Payload.roomProfile(name: "Bob's"), hash: 5, to: &roster)
        #expect(roster.name == "Bob's")
    }
}
