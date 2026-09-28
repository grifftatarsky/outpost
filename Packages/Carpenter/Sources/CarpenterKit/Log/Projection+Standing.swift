import Foundation

extension Projection {
    // MARK: Standing — what an absent member's entries count for

    struct AbsenceWindow {
        let opened: RenderedEntry
        var readmitted: RenderedEntry?
    }

    func absenceWindows(
        in room: RoomID, opening: (RenderedEntry) -> Payload?
    ) -> [ParticipantID: [AbsenceWindow]] {
        var roster = RoomRoster(room: room)
        var windows: [ParticipantID: [AbsenceWindow]] = [:]

        for entry in entries(in: room) {
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

    public func outOfRoom(in room: RoomID, opening: (RenderedEntry) -> Payload?) -> Set<EntryHash> {
        let windows = absenceWindows(in: room, opening: opening)
        guard !windows.isEmpty else { return [] }

        var out: Set<EntryHash> = []
        for entry in entries(in: room) {
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
        of room: RoomID,
        memberCount: Int? = nil,
        others: [ParticipantID] = [],
        unreadFor viewer: ParticipantID? = nil,
        readThrough: EntryHash? = nil,
        undrawn: Set<EntryHash> = []
    ) -> RoomSummary? {
        guard let positions = roomPositions[room], let newest = positions.last,
            let profile = lastProfiles[room], case .text(let stored) = profile.content
        else { return nil }
        let kind = kind(of: room)

        let partner = kind == .solo ? others.first(where: { $0 != self.viewer }).map(member) : nil
        let name = partner?.displayName ?? stored

        let last = positions.last { rendered[$0].isConversation }.map { rendered[$0] }

        return RoomSummary(
            id: room,
            name: name,
            memberCount: memberCount ?? Set(positions.map { rendered[$0].author }).count,
            lastAuthor: last.map { member($0.author) },
            lastMessage: last.map { preview($0) } ?? "",
            lastActivity: last?.wallTime ?? rendered[newest].wallTime,
            hasUnread: hasUnread(
                in: room, at: positions, for: viewer, readThrough: readThrough, undrawn: undrawn),
            isDirect: kind == .solo,
            initials: partner?.initials,
            partner: partner?.id,
            recentSpeakers: kind == .solo ? [] : recentSpeakers(at: positions)
        )
    }

    static let speakersShown = 3
    static let speakersSearched = 200

    private func recentSpeakers(at positions: [Int]) -> [Member] {
        var found: [ParticipantID] = []
        for position in positions.reversed().prefix(Self.speakersSearched) {
            let entry = rendered[position]
            guard entry.isConversation, entry.author != viewer, !found.contains(entry.author) else { continue }
            found.append(entry.author)
            if found.count == Self.speakersShown { break }
        }
        return found.map(member)
    }

    private func hasUnread(
        in room: RoomID, at positions: [Int], for viewer: ParticipantID?, readThrough: EntryHash?,
        undrawn: Set<EntryHash>
    ) -> Bool {
        guard let viewer else { return false }
        let mark = readThrough.flatMap { positionByID[$0] }
            .flatMap { rendered[$0].isConversation && rendered[$0].room == room ? $0 : nil }
        for position in positions.reversed() {
            if let mark, position <= mark { return false }
            let entry = rendered[position]
            guard entry.isConversation, entry.author != viewer, !undrawn.contains(entry.id) else { continue }
            if case .withdrawn = entry.content { continue }
            return true
        }
        return false
    }
}
