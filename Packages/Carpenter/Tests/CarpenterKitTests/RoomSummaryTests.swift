@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Room summaries", .tags(.ui))
@MainActor
struct RoomSummaryTests {
    @Test("The room list the session publishes names every room it holds")
    func theRoomListNamesEveryRoom() async throws {
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        let first = try await alice.createRoom(named: "Room 0")
        var made: Set<RoomID> = [first]
        for index in 1..<4 { made.insert(try await alice.createRoom(named: "Room \(index)")) }
        try await alice.send("hello", to: first)

        #expect(Set(alice.rooms.map(\.id)) == made)
        #expect(Set(alice.rooms.map(\.name)) == ["Room 0", "Room 1", "Room 2", "Room 3"])
    }
}

@Suite("A room summary read from the projection's index", .tags(.ui))
struct RoomSummaryIndexTests {
    private func referenceSummary(
        _ projected: Projection, of room: RoomID, named stored: String, others: [ParticipantID],
        viewer: ParticipantID?, readThrough: EntryHash?, undrawn: Set<EntryHash>, out: Set<EntryHash>
    ) -> RoomSummary? {
        let inRoom = projected.rendered.filter { $0.room == room }
        guard let kind = inRoom.first(where: { $0.founds != nil })?.founds else { return nil }
        let drawn = { (entry: RenderedEntry) in
            !undrawn.contains(entry.id) && (!out.contains(entry.id) || entry.author == projected.viewer)
        }
        let partner = kind == .solo ? others.first(where: { $0 != projected.viewer }).map(projected.member) : nil
        let conversation = inRoom.filter(\.isConversation)
        let said = conversation.filter(drawn)
        let last = said.last
        var unread = false
        if let viewer {
            let mark = readThrough.flatMap { hash in conversation.firstIndex { $0.id == hash } }
            unread = conversation[(mark.map { $0 + 1 } ?? 0)...].contains { entry in
                guard entry.author != viewer, drawn(entry) else { return false }
                if case .withdrawn = entry.content { return false }
                return true
            }
        }
        return RoomSummary(
            id: room, name: partner?.displayName ?? stored,
            memberCount: Set(inRoom.map(\.author)).count,
            lastAuthor: last.map { projected.member($0.author) },
            lastMessage: last.map { projected.preview($0) } ?? "",
            lastActivity: last?.wallTime ?? (inRoom.last(where: drawn) ?? inRoom.first)?.wallTime ?? .distantPast,
            hasUnread: unread, isDirect: kind == .solo, initials: partner?.initials, partner: partner?.id,
            recentSpeakers: kind == .solo ? [] : speakers(in: said, viewer: projected.viewer).map(projected.member))
    }

    private func speakers(in conversation: [RenderedEntry], viewer: ParticipantID?) -> [ParticipantID] {
        var found: [ParticipantID] = []
        for entry in conversation.reversed() where entry.author != viewer && !found.contains(entry.author) {
            found.append(entry.author)
        }
        return Array(found.prefix(3))
    }

    @Test("Every summary agrees with one worked out from the room's whole history")
    func summariesMatchTheWholeHistory() {
        var random = Seeded(state: 7)
        let people = (1...3).map { ParticipantID(rawValue: WideID.of([UInt8($0)])) }
        let rooms = (0..<3).map { _ in RoomID() }
        for round in 0..<150 {
            var rendered: [RenderedEntry] = []
            for index in 0..<Int.random(in: 1...40, using: &random) {
                let type: PayloadType = [.roomProfile, .post, .post, .post, .memberProfile].randomElement(using: &random)!
                let content: RenderedContent = [.text("\(index)"), .text("hi"), .withdrawn, .sealed].randomElement(using: &random)!
                var entry = RenderedEntry(
                    id: EntryHash(rawValue: WideID.of([UInt8(round % 256), UInt8(index)])), type: type,
                    author: people.randomElement(using: &random)!, device: DeviceID(rawValue: WideID.of([9])),
                    wallTime: Date(timeIntervalSince1970: Double(index)), room: rooms.randomElement(using: &random)!,
                    content: content, editedAt: nil, replyingTo: nil, reactions: [:])
                if type == .roomProfile { entry.founds = Bool.random(using: &random) ? RoomKind.solo : .room }
                rendered.append(entry)
            }
            let viewer = Bool.random(using: &random) ? people[0] : nil
            let projected = Projection(viewer: people[0], rendered: rendered)
            let marks = rendered.map(\.id) + [EntryHash(rawValue: WideID.of([0xEE]))]
            for room in rooms {
                let readThrough = Bool.random(using: &random) ? marks.randomElement(using: &random) : nil
                let undrawn = Set(rendered.map(\.id).filter { _ in Int.random(in: 0..<5, using: &random) == 0 })
                let out = Set(rendered.map(\.id).filter { _ in Int.random(in: 0..<4, using: &random) == 0 })
                let others = Array(people.shuffled(using: &random).prefix(2))
                #expect(
                    projected.summary(
                        of: room, named: "Room", others: others, unreadFor: viewer, readThrough: readThrough,
                        undrawn: undrawn, outOfRoom: out)
                        == referenceSummary(
                            projected, of: room, named: "Room", others: others, viewer: viewer,
                            readThrough: readThrough, undrawn: undrawn, out: out),
                    "round \(round)")
            }
        }
    }
}

@Suite("What a projection knows from its first pass", .tags(.ui))
struct ProjectionFirstPassTests {
    private func entry(
        _ index: UInt8, by author: ParticipantID, in room: RoomID?, type: PayloadType = .post,
        content: RenderedContent = .text("hi")
    ) -> RenderedEntry {
        RenderedEntry(
            id: EntryHash(rawValue: WideID.of([7, index])), type: type, author: author,
            device: DeviceID(rawValue: WideID.of([8])), wallTime: Date(timeIntervalSince1970: Double(index)),
            room: room, content: content, editedAt: nil, replyingTo: nil, reactions: [:])
    }

    @Test("Outpost authors come most recent first, the viewer ahead of everyone")
    func outpostAuthorsInOrder() {
        let viewer = ParticipantID(rawValue: WideID.of([1]))
        let ann = ParticipantID(rawValue: WideID.of([2]))
        let ben = ParticipantID(rawValue: WideID.of([3]))
        let projected = Projection(
            viewer: viewer,
            rendered: [
                entry(1, by: ann, in: nil), entry(2, by: ben, in: nil), entry(3, by: viewer, in: nil),
                entry(4, by: ann, in: nil), entry(5, by: ben, in: RoomID()),
            ])

        #expect(projected.outpostAuthors().map(\.id) == [viewer, ann, ben])
    }

    @Test("A room is listed once the profile that founds it can be read, and not before")
    func namedRooms() {
        let viewer = ParticipantID(rawValue: WideID.of([1]))
        let kitchen = RoomID()
        let hangar = RoomID()
        let attic = RoomID()
        func founding(_ entry: RenderedEntry) -> RenderedEntry {
            var founding = entry
            founding.founds = .room
            return founding
        }
        let projected = Projection(
            viewer: viewer,
            rendered: [
                founding(entry(1, by: viewer, in: kitchen, type: .roomProfile, content: .text("Kitchen"))),
                founding(entry(2, by: viewer, in: hangar, type: .roomProfile, content: .text("Hangar"))),
                entry(3, by: viewer, in: hangar, type: .roomProfile, content: .sealed),
                entry(4, by: viewer, in: attic, type: .roomProfile, content: .text("Attic")),
            ])

        #expect(projected.namedRoomIDs() == [kitchen, hangar], "a room nobody founded was listed")
        #expect(projected.summary(of: attic, named: "Attic") == nil)
    }
}
