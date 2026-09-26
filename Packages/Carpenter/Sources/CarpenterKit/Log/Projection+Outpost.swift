import Foundation

extension Projection {
    // MARK: Who sees an Outpost

    public func outpostAccess(
        of owner: ParticipantID, opening: (RenderedEntry) -> Payload?
    ) -> OutpostAccess {
        var access = OutpostAccess()
        for change in accessChanges(of: owner, opening: opening) {
            let stamp = OrganisationStamp(at: change.at, device: change.device)
            if change.body.isAllowed {
                access.allow(
                    change.body.person, from: change.body.from, origin: change.body.origin,
                    chosenIn: change.body.chosenIn, stamp: stamp)
            } else {
                access.revoke(change.body.person, chosenIn: change.body.chosenIn, stamp: stamp)
            }
        }
        return access
    }

    public func outpostFloors(
        of owner: ParticipantID, opening: (RenderedEntry) -> Payload?
    ) -> [ParticipantID: UInt64?] {
        var floors: [ParticipantID: UInt64?] = [:]
        for change in accessChanges(of: owner, opening: opening) where change.body.isAllowed {
            floors[change.body.person] = change.body.sinceEpoch
        }
        return floors
    }

    private func accessChanges(
        of owner: ParticipantID, opening: (RenderedEntry) -> Payload?
    ) -> [(body: OutpostAccessBody, at: Date, device: DeviceID)] {
        let wall = RoomID.outpost(of: owner)
        var changes: [(OutpostAccessBody, Date, DeviceID)] = []
        for entry in rendered
        where (entry.room == nil || entry.room == wall) && entry.author == owner
            && entry.type == .outpostAccess {
            guard let payload = opening(entry),
                let body = try? payload.decode(OutpostAccessBody.self)
            else { continue }
            changes.append((body, entry.wallTime, entry.device))
        }
        return changes
    }

    public func posts(by author: ParticipantID) -> [OutpostPost] {
        posts(outpostEntries.filter { $0.author == author })
    }

    public func feed() -> [OutpostPost] {
        posts(outpostEntries)
    }

    private func posts(_ entries: [RenderedEntry]) -> [OutpostPost] {
        var replies: [EntryHash: [RenderedEntry]] = [:]
        for entry in rendered where entry.type == .comment && entry.isReadable {
            if let target = entry.replyingTo { replies[target, default: []].append(entry) }
        }
        return entries.map { post($0, replies: replies[$0.id] ?? []) }
    }

    public func outpostAuthors() -> [Member] {
        let others = outpostAuthorOrder.filter { $0 != viewer }.map(member)
        return (outpostAuthorOrder.contains(viewer) ? [member(viewer)] : []) + others
    }

    private var outpostEntries: [RenderedEntry] {
        rendered.filter { $0.room == nil && $0.isConversation && $0.isReadable }.reversed()
    }

    private func post(_ entry: RenderedEntry, replies entries: [RenderedEntry]) -> OutpostPost {
        let replies = entries.map(comment)
        let media: [MediaAttachment]
        let body: String
        if case .media(let photo) = entry.content {
            media = photo.all.map(MediaAttachment.init)
            body = photo.caption ?? ""
        } else {
            media = []
            body = preview(entry, withdrawn: Self.withdrawnPost)
        }
        return OutpostPost(
            id: PostID(entry: entry.id),
            author: member(entry.author),
            body: body,
            postedAt: entry.wallTime,
            commentCount: replies.count,
            previewComments: Array(replies.prefix(2)),
            reactions: entry.reactions,
            isMine: entry.author == viewer,
            media: media,
            editedAt: entry.editedAt,
            isWithdrawn: Self.isWithdrawn(entry)
        )
    }

    public func comments(on target: EntryHash) -> [OutpostComment] {
        rendered
            .filter { $0.type == .comment && $0.replyingTo == target && $0.isReadable }
            .map(comment)
    }

    private func comment(_ entry: RenderedEntry) -> OutpostComment {
        OutpostComment(
            id: PostID(entry: entry.id),
            author: member(entry.author),
            body: preview(entry, withdrawn: Self.withdrawnComment),
            postedAt: entry.wallTime,
            reactions: entry.reactions,
            isMine: entry.author == viewer,
            editedAt: entry.editedAt,
            isWithdrawn: Self.isWithdrawn(entry)
        )
    }
}
