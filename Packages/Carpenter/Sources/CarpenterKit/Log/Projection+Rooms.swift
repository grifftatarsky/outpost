import Foundation

extension Projection {
    // MARK: Rooms

    public func entry(_ hash: EntryHash) -> RenderedEntry? {
        rendered.first { $0.id == hash }
    }

    public func roomIDs() -> Set<RoomID> {
        Set(rendered.compactMap(\.room))
    }

    public func entries(by authors: Set<ParticipantID>, in room: RoomID) -> Set<EntryHash> {
        guard !authors.isEmpty else { return [] }
        return Set(rendered.lazy.filter { $0.room == room && authors.contains($0.author) }.map(\.id))
    }

    public func name(of room: RoomID) -> String? {
        rendered.last { $0.room == room && $0.type == .roomProfile }
            .flatMap { if case .text(let name) = $0.content { name } else { nil } }
    }

    public func kind(of room: RoomID) -> RoomKind {
        rendered.first { $0.room == room && $0.type == .roomProfile }?.roomKind ?? .room
    }

    public func roster(of room: RoomID, opening: (RenderedEntry) -> Payload?) -> RoomRoster {
        var roster = RoomRoster(room: room)
        for entry in rendered where entry.room == room {
            if let payload = opening(entry) { roster.apply(entry, body: payload) }
        }
        return roster
    }

    public func soloCheck(in room: RoomID, opening: (RenderedEntry) -> Payload?) -> SoloCheck {
        var check = SoloCheck()
        for entry in rendered
        where entry.room == room && SoloCheck.shaping.contains(entry.type) {
            if let payload = opening(entry) { check.apply(entry, body: payload) }
        }
        return check
    }

    public func soloChecksAwaiting(
        in room: RoomID, opening: (RenderedEntry) -> Payload?
    ) -> [(id: EntryHash, asker: ParticipantID, at: Date)] {
        var open: [EntryHash: (ParticipantID, Date)] = [:]
        var answered: Set<EntryHash> = []
        for entry in rendered
        where entry.room == room && SoloCheck.shaping.contains(entry.type) {
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
