import Foundation

extension Projection {
    // MARK: Names

    public var members: [ParticipantID: Member] {
        var names: [ParticipantID: Member] = [:]
        for entry in rendered where entry.type == .memberProfile {
            if case .text(let name) = entry.content, !name.isEmpty {
                names[entry.author] = Member(id: entry.author, displayName: name)
            }
        }
        return names
    }

    public func member(_ id: ParticipantID) -> Member {
        if id == viewer, let viewerName, !viewerName.isEmpty {
            return Member(id: id, displayName: viewerName)
        }
        if let met, id != viewer, !met.contains(id) { return .anonymous(anonPersona) }
        if id != viewer, let nickname = nicknames[id] {
            return Member(id: id, displayName: nickname)
        }
        guard revealsNames || id == viewer else { return Member.placeholder(id) }
        return members[id] ?? Member.placeholder(id)
    }

    public var visibleMembers: [ParticipantID: Member] {
        var named = revealsNames ? members : members.filter { $0.key == viewer }
        if let met {
            named = named.filter { $0.key == viewer || met.contains($0.key) }
        }

        if let viewerName, !viewerName.isEmpty {
            named[viewer] = Member(id: viewer, displayName: viewerName)
        }
        for (person, nickname) in nicknames where person != viewer {
            named[person] = Member(id: person, displayName: nickname)
        }
        return named
    }

    public func peopleInRooms(opening: (RenderedEntry) -> Payload?) -> Set<ParticipantID> {
        var rosters: [RoomID: RoomRoster] = [:]
        for entry in rendered {
            guard let room = entry.room, RoomRoster.rosterShaping.contains(entry.type) else {
                continue
            }
            guard let payload = opening(entry) else { continue }
            rosters[room, default: RoomRoster(room: room)].apply(entry, body: payload)
        }
        var people: Set<ParticipantID> = []
        for roster in rosters.values {
            people.formUnion(roster.members)
            people.formUnion(roster.absent)
            people.formUnion(roster.requests.keys)
        }
        return people
    }

    public func naming() -> (ParticipantID) -> Member {
        let named = visibleMembers
        let met = met
        let persona = anonPersona
        let viewer = viewer
        return { id in
            if let named = named[id] { return named }
            if let met, id != viewer, !met.contains(id) { return .anonymous(persona) }
            return .placeholder(id)
        }
    }

    public func announcedName(of author: ParticipantID, in room: RoomID) -> String? {
        let last = rendered.last {
            $0.room == room && $0.type == .memberProfile && $0.author == author
        }
        if case .text(let name) = last?.content, !name.isEmpty { return name }
        return nil
    }

    public func commentTally(
        for post: EntryHash, by owner: ParticipantID, opening: (RenderedEntry) -> Payload?
    ) -> Int? {
        let wall = RoomID.outpost(of: owner)
        let last = rendered.last { entry in
            guard entry.type == .commentTally, entry.author == owner,
                entry.room == nil || entry.room == wall
            else { return false }
            guard let payload = opening(entry),
                let body = try? payload.decode(CommentTallyBody.self)
            else { return false }
            return body.post == post
        }
        guard let last, let payload = opening(last),
            let body = try? payload.decode(CommentTallyBody.self)
        else { return nil }
        return body.total
    }

    public func commentCount(on target: EntryHash) -> Int {
        comments(on: target).count
    }

    public func blurb(of author: ParticipantID, opening: (RenderedEntry) -> Payload?) -> String? {
        let wall = RoomID.outpost(of: author)
        let last = rendered.last {
            $0.type == .memberProfile && $0.author == author && $0.room == wall
        }
        guard let last, let payload = opening(last),
            let body = try? payload.decode(MemberProfileBody.self),
            let blurb = body.blurb?.trimmingCharacters(in: .whitespacesAndNewlines),
            !blurb.isEmpty
        else { return nil }
        return blurb
    }

    public func photoReference(of author: ParticipantID) -> AttachmentReference? {
        let wall = RoomID.outpost(of: author)
        return rendered.last { $0.type == .memberPhoto && $0.author == author && $0.room != wall }?
            .memberPhoto?.reference
    }

    public func outpostPhotoReference(of author: ParticipantID) -> AttachmentReference? {
        let wall = RoomID.outpost(of: author)
        return rendered.last { $0.type == .memberPhoto && $0.author == author && $0.room == wall }?
            .memberPhoto?.reference
    }

    public func announcedPhoto(of author: ParticipantID, in room: RoomID) -> AttachmentReference?? {
        rendered.last { $0.room == room && $0.type == .memberPhoto && $0.author == author }?.memberPhoto
            .map(\.reference)
    }

    public func focusStatus(of author: ParticipantID) -> FocusStatusBody? {
        rendered.last { $0.type == .focusStatus && $0.author == author }?.focusStatus
    }

    public func lastFocusStatus(of author: ParticipantID, in room: RoomID) -> FocusStatusBody? {
        rendered.last { $0.room == room && $0.type == .focusStatus && $0.author == author }?.focusStatus
    }

    public var supporterBadges: Set<ParticipantID> {
        var latest: [ParticipantID: Bool] = [:]
        for entry in rendered where entry.type == .supporterBadge {
            guard let badge = entry.supporterBadge else { continue }
            latest[entry.author] = badge.shows
        }
        return Set(latest.filter(\.value).keys)
    }

    public func lastSupporterBadge(of author: ParticipantID, in room: RoomID) -> SupporterBadgeBody? {
        rendered.last { $0.room == room && $0.type == .supporterBadge && $0.author == author }?.supporterBadge
    }
}
