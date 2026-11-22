@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("A room is founded by the person its ID names")
struct ARoomIsFoundedByThePersonItsIDNamesTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private struct Log {
        var roster: RoomRoster
        var hash: UInt8 = 1
        let start: Date

        mutating func write(_ author: Identity, _ type: PayloadType, _ body: Payload) {
            roster.apply(
                RenderedEntry(
                    id: EntryHash(rawValue: Data(repeating: hash, count: 32)), type: type, author: author.id,
                    device: DeviceID(rawValue: WideID.of([])), wallTime: start, room: roster.room,
                    content: .text(""), editedAt: nil, replyingTo: nil, reactions: [:]),
                body: body)
            hash &+= 1
        }

        mutating func invite(_ joiner: Identity, by inviter: Identity) throws {
            let invite = try TestInvite.issue(joining: roster.room, joinerKeys: joiner.publicKeys, by: inviter, at: start)
            write(inviter, .joinRequest, try Payload.joinRequest(invite))
            write(inviter, .joinConfirmed, try Payload.joinConfirmed(try JoinConfirmedBody.signed(confirming: invite, by: joiner)))
        }
    }

    @Test("A profile that comes first in the log does not make its writer the founder", arguments: [false, true])
    func theFirstProfileIsNotTheFounder(copyingTheFounding: Bool) throws {
        let (alice, bob, mallory) = (Identity.generate(), Identity.generate(), Identity.generate())
        let (room, founding) = RoomID.founding(by: alice.id, as: .room)
        var log = Log(roster: RoomRoster(room: room), start: start)

        log.write(
            mallory, .roomProfile,
            try Payload.roomProfile(
                name: "Mallory's", founding: copyingTheFounding ? founding : RoomID.founding(by: mallory.id, as: .room).founding))
        log.write(alice, .roomProfile, try Payload.roomProfile(name: "Hangar 7", founding: founding))
        try log.invite(bob, by: alice)
        try log.invite(mallory, by: alice)

        #expect(log.roster.founder == alice.id, "a profile written ahead of the founder's made its writer the founder")
        #expect(log.roster.members == [alice.id, bob.id, mallory.id])
    }

    @Test("A room whose profile carries no founding has nobody in it")
    func anUnfoundedRoomIsEmpty() throws {
        let alice = Identity.generate()
        var log = Log(roster: RoomRoster(room: RoomID()), start: start)

        log.write(alice, .roomProfile, try Payload.roomProfile(name: "Hangar 7"))

        #expect(log.roster.founder == nil)
        #expect(log.roster.members.isEmpty)
    }

    @Test("A room's kind and its first notice come from the profile that founds it, wherever another sorts")
    func theKindIsTheFoundersChoice() throws {
        let (alice, mallory) = (Identity.generate(), Identity.generate())
        let (room, founding) = RoomID.founding(by: alice.id, as: .solo)
        let chain = EpochChain.create(room: room).chain
        func written(by identity: Identity, _ payload: Payload, at offset: TimeInterval) throws -> Entry {
            try Entry.append(
                after: nil, author: identity.id, device: DeviceKeys.generate(), clock: VectorClock(),
                wallTime: start.addingTimeInterval(offset), room: room, payload: payload, at: .initial,
                sealedWith: chain, roomLink: RoomLink(previous: nil))
        }
        let entries = [
            try written(by: mallory, try Payload.roomProfile(name: "Mallory's", kind: .room), at: -60),
            try written(by: alice, try Payload.roomProfile(name: "Alice", kind: .solo, founding: founding), at: 0),
        ]

        let projected = Projection(viewer: alice.id, rendered: LogRenderer.render(entries, using: chain))

        #expect(projected.kind(of: room) == .solo, "a profile written ahead of the founder's chose the room's kind")
        let opening = { (rendered: RenderedEntry) in entries.first { $0.hash == rendered.id }?.opened(using: chain) }
        let first = projected.transcript(in: room, opening: opening).compactMap { item -> RoomNotice.Kind? in
            if case .notice(let notice) = item { return notice.kind }
            return nil
        }.first
        guard case .startedSolo(let by) = first else {
            Issue.record("the room's first notice is not the founder starting it: \(String(describing: first))")
            return
        }
        #expect(by.id == alice.id)
    }

    @Test("The founding number has its size, and no other")
    func theFoundingHasItsSize() throws {
        let alice = Identity.generate()
        let short = Data(repeating: 7, count: RoomID.foundingBytes - 1)
        let room = RoomID.founded(by: alice.id, as: .room, founding: short)
        #expect(!RoomProfileBody(name: "Hangar 7", kind: .room, founding: short).founds(room, by: alice.id))
    }
}

@MainActor
@Suite("A room is made bound to its founder", .serialized)
struct ARoomIsMadeBoundToItsFounderTests {
    @Test("A room the app makes is founded by the person who made it, as the kind they chose", arguments: [RoomKind.room, .solo])
    func aNewRoomNamesItsFounder(kind: RoomKind) async throws {
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let room = try await alice.createRoom(named: "Hangar 7", kind: kind)

        #expect(alice.roster(of: room).founder == alice.enrolment?.identity.id)
        #expect(alice.projection.kind(of: room) == kind)
    }

    @Test("A reader cannot make somebody's Outpost into a room")
    func aReaderCannotFoundAWall() async throws {
        let mailbox = InMemoryMailbox()
        let (alice, bob) = (TestSession.make(), TestSession.make())
        for (session, name) in [(alice, "Alice"), (bob, "Bob")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        try await join(alice, into: try await bob.createRoom(named: "Lanterns"), of: bob, through: mailbox)
        let aliceID = try #require(alice.enrolment?.identity.id)
        let bobID = try #require(bob.enrolment?.identity.id)
        try await bob.allowOutpost(aliceID, everything: true)
        for _ in 0..<5 {
            for session in [alice, bob] { try await session.sync(through: mailbox, media: mailbox) }
        }
        let wall = RoomID.outpost(of: bobID)
        try #require(alice.chains[wall] != nil, "precondition: Alice reads Bob's Outpost")

        try await alice.append(try Payload.roomProfile(name: "Alice's now"), to: wall, isWall: true)
        for _ in 0..<5 {
            for session in [alice, bob] { try await session.sync(through: mailbox, media: mailbox) }
        }

        #expect(!bob.rooms.contains { $0.id == wall }, "Bob's Outpost appeared in his rooms list as a room Alice made")
        #expect(bob.roster(of: wall).founder == nil)
        #expect(bob.roster(of: wall).members.isEmpty)
    }
}
