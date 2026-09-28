import Foundation

extension Projection {
    // MARK: Rooms

    public func entry(_ hash: EntryHash) -> RenderedEntry? {
        positionByID[hash].map { rendered[$0] }
    }

    public func roomIDs() -> [RoomID] {
        Array(roomPositions.keys)
    }

    public func entries(by authors: Set<ParticipantID>, in room: RoomID) -> Set<EntryHash> {
        guard !authors.isEmpty else { return [] }
        return Set(entries(in: room).filter { authors.contains($0.author) }.map(\.id))
    }

    public func namedRoomIDs() -> Set<RoomID> {
        namedRooms
    }

    public func name(of room: RoomID) -> String? {
        lastProfiles[room].flatMap { if case .text(let name) = $0.content { name } else { nil } }
    }

    public func kind(of room: RoomID) -> RoomKind {
        roomKinds[room] ?? .room
    }

    public func roster(of room: RoomID, opening: (RenderedEntry) -> Payload?) -> RoomRoster {
        standing(in: room, opening: opening).roster
    }

    public func soloCheck(in room: RoomID, opening: (RenderedEntry) -> Payload?) -> SoloCheck {
        var check = SoloCheck()
        for entry in entries(in: room)
        where SoloCheck.entryTypes.contains(entry.type) {
            if let payload = opening(entry) { check.apply(entry, body: payload) }
        }
        return check
    }

    public func soloChecksAwaiting(
        in room: RoomID, opening: (RenderedEntry) -> Payload?
    ) -> [(id: EntryHash, asker: ParticipantID, at: Date)] {
        var open: [EntryHash: (ParticipantID, Date)] = [:]
        var answered: Set<EntryHash> = []
        for entry in entries(in: room)
        where SoloCheck.entryTypes.contains(entry.type) {
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

extension Projection {
    public func pairLinks(in room: RoomID, to recipient: ParticipantID) -> [(entry: RenderedEntry, body: PairLinkBody)] {
        entries(in: room).compactMap { entry in
            guard entry.type == .pairLink, entry.author != recipient, let body = entry.pairLink, body.recipient == recipient
            else { return nil }
            return (entry, body)
        }
    }
}
