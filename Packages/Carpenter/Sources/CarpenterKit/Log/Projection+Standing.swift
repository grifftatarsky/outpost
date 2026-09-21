import Foundation

extension Projection {
    // MARK: Standing — what an absent member's entries count for

    struct AbsenceWindow {
        let opened: RenderedEntry
        var readmitted: RenderedEntry?
    }

    func absenceWindows(
        in room: ConversationID, opening: (RenderedEntry) -> Payload?
    ) -> [ParticipantID: [AbsenceWindow]] {
        var roster = RoomRoster(room: room)
        var windows: [ParticipantID: [AbsenceWindow]] = [:]

        for entry in rendered where entry.room == room {
            guard let payload = opening(entry) else { continue }
            let before = roster.absent
            roster.apply(entry, body: payload)
            let after = roster.absent

            for person in after.subtracting(before) {
                windows[person, default: []].append(AbsenceWindow(opened: entry, readmitted: nil))
            }
            for person in before.subtracting(after) {
                guard var theirs = windows[person], var open = theirs.last, open.readmitted == nil
                else { continue }
                open.readmitted = entry
                theirs[theirs.count - 1] = open
                windows[person] = theirs
            }
        }
        return windows
    }

    static func isAfter(_ entry: RenderedEntry, _ leaving: RenderedEntry) -> Bool {
        if leaving.seq > 0, entry.clock[leaving.feedKey] >= leaving.seq { return true }
        if entry.seq > 0, leaving.clock[entry.feedKey] >= entry.seq { return false }
        if entry.wallTime != leaving.wallTime { return entry.wallTime > leaving.wallTime }
        return leaving.id.rawValue.lexicographicallyPrecedes(entry.id.rawValue)
    }

    static func isAfterReadmission(_ entry: RenderedEntry, _ readmitted: RenderedEntry?) -> Bool {
        guard let readmitted, readmitted.seq > 0, entry.seq > 0 else { return false }
        return entry.clock[readmitted.feedKey] >= readmitted.seq
            && readmitted.clock[entry.feedKey] < entry.seq
    }

    public func outOfRoom(in room: ConversationID, opening: (RenderedEntry) -> Payload?) -> Set<EntryHash> {
        let windows = absenceWindows(in: room, opening: opening)
        guard !windows.isEmpty else { return [] }

        var out: Set<EntryHash> = []
        for entry in rendered where entry.room == room {
            guard let theirs = windows[entry.author] else { continue }
            let isOut = theirs.contains { window in
                entry.id != window.opened.id
                    && Self.isAfter(entry, window.opened)
                    && !Self.isAfterReadmission(entry, window.readmitted)
            }
            if isOut { out.insert(entry.id) }
        }
        return out
    }

    public func summaries() -> [RoomSummary] {
        roomIDs().compactMap { summary(of: $0) }
    }

    public func summary(
        of room: ConversationID,
        memberCount: Int? = nil,
        others: [ParticipantID] = [],
        unreadFor viewer: ParticipantID? = nil,
        readThrough: EntryHash? = nil,
        undrawn: Set<EntryHash> = []
    ) -> RoomSummary? {
        let inRoom = rendered.filter { $0.room == room }
        guard let stored = name(of: room) else { return nil }
        let kind = kind(of: room)

        let partner = kind == .solo ? others.first(where: { $0 != self.viewer }).map(member) : nil
        let name = partner?.displayName ?? stored

        let conversation = inRoom.filter(\.isConversation)
        let last = conversation.last

        return RoomSummary(
            id: room,
            name: name,
            memberCount: memberCount ?? Set(inRoom.map(\.author)).count,
            lastAuthor: last.map { member($0.author) },
            lastMessage: last.map { preview($0) } ?? "",
            lastActivity: last?.wallTime ?? inRoom.last?.wallTime ?? .distantPast,
            hasUnread: Self.hasUnread(
                in: conversation, for: viewer, readThrough: readThrough, undrawn: undrawn),
            isDirect: kind == .solo,
            initials: partner?.initials,
            partner: partner?.id
        )
    }

    static func hasUnread(
        in conversation: [RenderedEntry],
        for viewer: ParticipantID?,
        readThrough: EntryHash?,
        undrawn: Set<EntryHash>
    ) -> Bool {
        guard let viewer else { return false }
        let mark = readThrough.flatMap { hash in conversation.firstIndex { $0.id == hash } }
        return conversation[(mark.map { $0 + 1 } ?? 0)...].contains { entry in
            guard entry.author != viewer, !undrawn.contains(entry.id) else { return false }
            if case .withdrawn = entry.content { return false }
            return true
        }
    }
}
