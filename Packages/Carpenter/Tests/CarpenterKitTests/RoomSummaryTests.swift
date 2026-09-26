@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Room summaries")
@MainActor
struct RoomSummaryTests {
    @Test("Summarising every room at once agrees with summarising each room alone")
    func groupedAgreesWithOneAtATime() async throws {
        let alice = TestSession.make()
        await alice.load()
        try await alice.createIdentity(displayName: "Alice")
        for index in 0..<5 {
            let room = try await alice.createRoom(named: "Room \(index)", kind: index == 3 ? .solo : .room)
            for message in 0..<index { try await alice.send("message \(message)", to: room) }
        }

        let projected = alice.projection
        let grouped = projected.summaries().sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        let alone = projected.roomIDs().compactMap { projected.summary(of: $0) }
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }

        #expect(grouped.count == 5)
        #expect(grouped == alone)
    }

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

@Suite("A room summary read from the projection's index")
struct RoomSummaryIndexTests {
    private func referenceSummary(
        _ projected: Projection, of room: RoomID, others: [ParticipantID], viewer: ParticipantID?,
        readThrough: EntryHash?, undrawn: Set<EntryHash>
    ) -> RoomSummary? {
        let inRoom = projected.rendered.filter { $0.room == room }
        guard let profile = inRoom.last(where: { $0.type == .roomProfile }),
            case .text(let stored) = profile.content
        else { return nil }
        let kind = inRoom.first { $0.type == .roomProfile }?.roomKind ?? .room
        let partner = kind == .solo ? others.first(where: { $0 != projected.viewer }).map(projected.member) : nil
        let conversation = inRoom.filter(\.isConversation)
        let last = conversation.last
        var unread = false
        if let viewer {
            let mark = readThrough.flatMap { hash in conversation.firstIndex { $0.id == hash } }
            unread = conversation[(mark.map { $0 + 1 } ?? 0)...].contains { entry in
                guard entry.author != viewer, !undrawn.contains(entry.id) else { return false }
                if case .withdrawn = entry.content { return false }
                return true
            }
        }
        return RoomSummary(
            id: room, name: partner?.displayName ?? stored,
            memberCount: Set(inRoom.map(\.author)).count,
            lastAuthor: last.map { projected.member($0.author) },
            lastMessage: last.map { projected.preview($0) } ?? "",
            lastActivity: last?.wallTime ?? inRoom.last?.wallTime ?? .distantPast,
            hasUnread: unread, isDirect: kind == .solo, initials: partner?.initials, partner: partner?.id)
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
                if type == .roomProfile { entry.roomKind = Bool.random(using: &random) ? .solo : .room }
                rendered.append(entry)
            }
            let viewer = Bool.random(using: &random) ? people[0] : nil
            let projected = Projection(viewer: people[0], rendered: rendered)
            let marks = rendered.map(\.id) + [EntryHash(rawValue: WideID.of([0xEE]))]
            for room in rooms {
                let readThrough = Bool.random(using: &random) ? marks.randomElement(using: &random) : nil
                let undrawn = Set(rendered.map(\.id).filter { _ in Int.random(in: 0..<5, using: &random) == 0 })
                let others = Array(people.shuffled(using: &random).prefix(2))
                #expect(
                    projected.summary(
                        of: room, others: others, unreadFor: viewer, readThrough: readThrough, undrawn: undrawn)
                        == referenceSummary(
                            projected, of: room, others: others, viewer: viewer, readThrough: readThrough,
                            undrawn: undrawn),
                    "round \(round)")
            }
        }
    }
}

@Suite("What a projection knows from its first pass")
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

    @Test("A room is named by its latest profile, and a room whose latest profile is not a name is not listed")
    func namedRooms() {
        let viewer = ParticipantID(rawValue: WideID.of([1]))
        let kitchen = RoomID()
        let hangar = RoomID()
        let projected = Projection(
            viewer: viewer,
            rendered: [
                entry(1, by: viewer, in: kitchen, type: .roomProfile, content: .text("Kitchen")),
                entry(2, by: viewer, in: hangar, type: .roomProfile, content: .text("Hangar")),
                entry(3, by: viewer, in: hangar, type: .roomProfile, content: .sealed),
            ])

        #expect(projected.namedRoomIDs() == [kitchen])
        #expect(projected.name(of: kitchen) == "Kitchen")
        #expect(projected.name(of: hangar) == nil)
    }
}
