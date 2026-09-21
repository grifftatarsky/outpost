import Foundation

extension Projection {
    // MARK: Rooms

    public func entry(_ hash: EntryHash) -> RenderedEntry? {
        rendered.first { $0.id == hash }
    }

    public func roomIDs() -> Set<ConversationID> {
        Set(rendered.filter { $0.conversation != .outpost($0.author) }.map(\.conversation))
    }

    public func entries(by authors: Set<ParticipantID>, in room: ConversationID) -> Set<EntryHash> {
        guard !authors.isEmpty else { return [] }
        return Set(rendered.lazy.filter { $0.conversation == room && authors.contains($0.author) }.map(\.id))
    }

    public func entries(of type: PayloadType, by author: ParticipantID) -> [RenderedEntry] {
        rendered.filter { $0.type == type && $0.author == author }
    }

    public func name(of room: ConversationID) -> String? {
        rendered.last { $0.conversation == room && $0.type == .roomProfile }
            .flatMap { if case .text(let name) = $0.content { name } else { nil } }
    }

    public func kind(of room: ConversationID) -> RoomKind {
        switch room {
        case .solo: .solo
        case .room, .outpost: .room
        }
    }

    public func roster(of room: ConversationID, opening: (RenderedEntry) -> Payload?) -> RoomRoster {
        var roster = RoomRoster(room: room)
        for entry in rendered where entry.conversation == room {
            if let payload = opening(entry) { roster.apply(entry, body: payload) }
        }
        return roster
    }

    public func soloCheck(in room: ConversationID, opening: (RenderedEntry) -> Payload?) -> SoloCheck {
        var check = SoloCheck()
        for entry in rendered
        where entry.conversation == room && SoloCheck.shaping.contains(entry.type) {
            if let payload = opening(entry) { check.apply(entry, body: payload) }
        }
        return check
    }

    public func soloChecksAwaiting(
        in room: ConversationID, opening: (RenderedEntry) -> Payload?
    ) -> [(id: EntryHash, asker: ParticipantID, at: Date)] {
        var open: [EntryHash: (ParticipantID, Date)] = [:]
        var answered: Set<EntryHash> = []
        for entry in rendered
        where entry.conversation == room && SoloCheck.shaping.contains(entry.type) {
            guard let body = try? opening(entry)?.decode(SoloCheckBody.self) else { continue }
            switch body.move {
            case .asked: open[entry.id] = (entry.author, entry.wallTime)
            case .confirmed, .refused:
                if let asked = body.answering { answered.insert(asked) }
            }
        }
        return open
            .filter { !answered.contains($0.key) }
            .map { (id: $0.key, asker: $0.value.0, at: $0.value.1) }
            .sorted {
                $0.at == $1.at
                    ? $0.asker.rawValue.lexicographicallyPrecedes($1.asker.rawValue) : $0.at < $1.at
            }
    }
}
