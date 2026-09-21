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
        let wall = ConversationID.outpost(of: owner)
        var changes: [(OutpostAccessBody, Date, DeviceID)] = []
        for entry in rendered
        where (entry.conversation == .outpost(entry.author) || entry.conversation == wall) && entry.author == owner
            && entry.type == .outpostAccess {
            guard let payload = opening(entry),
                let body = try? payload.decode(OutpostAccessBody.self)
            else { continue }
            changes.append((body, entry.wallTime, entry.device))
        }
        return changes
    }

    public func posts(by author: ParticipantID) -> [OutpostPost] {
        outpostEntries.filter { $0.author == author }.map(post)
    }

    public func feed() -> [OutpostPost] {
        outpostEntries.map(post)
    }

    public func outpostAuthors() -> [Member] {
        var seen: [ParticipantID] = []
        for entry in outpostEntries where !seen.contains(entry.author) {
            seen.append(entry.author)
        }
        let others = seen.filter { $0 != viewer }.map(member)
        return (seen.contains(viewer) ? [member(viewer)] : []) + others
    }

    private var outpostEntries: [RenderedEntry] {
        rendered.filter { $0.conversation == .outpost($0.author) && $0.isConversation && $0.isReadable }.reversed()
    }

    private func post(_ entry: RenderedEntry) -> OutpostPost {
        let replies = comments(on: entry.id)
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
            .map { entry in
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
}
