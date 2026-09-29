import Foundation

extension Projection {
    // MARK: Standing — who is in a room, and what counts from those who are not

    struct Standing {
        var roster: RoomRoster
        var out: Set<EntryHash> = []
    }

    public static let claimTypes: Set<PayloadType> = [.removal, .departure]

    private static let readForStanding = RoomRoster.rosterShaping.union([.removalNoted])

    private struct Claim {
        let entry: RenderedEntry
        let subject: ParticipantID
        let line: Set<EntryHash>

        func cuts(_ other: RenderedEntry) -> Bool {
            other.author == subject && other.id != entry.id && !line.contains(other.id)
        }
    }

    private struct Walk {
        var standing: Standing
        var took: Set<Int> = []
        var voidedBy: [Int: Set<Int>] = [:]
    }

    private struct Note {
        let entry: RenderedEntry
        let removal: EntryHash
        let storedAt: Date
    }

    func standing(in room: RoomID, opening: (RenderedEntry) -> Payload?) -> Standing {
        var payloads: [EntryHash: Payload] = [:]
        for entry in entries(in: room) where Self.readForStanding.contains(entry.type) {
            payloads[entry.id] = opening(entry)
        }
        let claims: [Claim] = entries(in: room).compactMap { claim($0, payloads[$0.id]) }
        let notes: [Note] = entries(in: room).compactMap { note($0, payloads[$0.id]) }
        let authors = Dictionary(
            claims.map { ($0.entry.id, $0.entry.author) }, uniquingKeysWith: { first, _ in first })

        var cutting = Set(claims.indices)
        while true {
            let walked = walk(room, claims: claims, cutting: cutting, payloads: payloads)
            let voided = Set(walked.voidedBy.keys).intersection(cutting)
            let idle = cutting.subtracting(walked.took).subtracting(voided)
            let defeated = voided.filter { !(walked.voidedBy[$0] ?? []).isSubset(of: voided) }
            if !idle.isEmpty {
                cutting.subtract(idle)
            } else if !defeated.isEmpty {
                cutting.subtract(defeated)
            } else if let first = firstOf(
                voided, in: claims, noted: Self.earliest(notes, besides: walked.standing.out, authors: authors))
            {
                cutting.subtract(walked.voidedBy[first] ?? [])
            } else {
                return walked.standing
            }
        }
    }

    private func firstOf(_ voided: Set<Int>, in claims: [Claim], noted: [EntryHash: Date]) -> Int? {
        voided.min { comesFirst(claims[$0].entry, claims[$1].entry, noted: noted) }
    }

    func comesFirst(_ one: RenderedEntry, _ other: RenderedEntry, noted: [EntryHash: Date]) -> Bool {
        let yoursUnnoted = { (claim: RenderedEntry) in claim.author == viewer && noted[claim.id] == nil }
        if yoursUnnoted(one) != yoursUnnoted(other) { return yoursUnnoted(one) }
        let stored = { (claim: RenderedEntry) in noted[claim.id] ?? claimTimes[claim.id] ?? .distantFuture }
        if stored(one) != stored(other) { return stored(one) < stored(other) }
        return one.id.rawValue.lexicographicallyPrecedes(other.id.rawValue)
    }

    private static func earliest(
        _ notes: [Note], besides out: Set<EntryHash>, authors: [EntryHash: ParticipantID]
    ) -> [EntryHash: Date] {
        var noted: [EntryHash: Date] = [:]
        for note in notes where !out.contains(note.entry.id) {
            guard let author = authors[note.removal], author != note.entry.author else { continue }
            noted[note.removal] = min(noted[note.removal] ?? note.storedAt, note.storedAt)
        }
        return noted
    }

    public func noters(of removal: EntryHash, in room: RoomID, opening: (RenderedEntry) -> Payload?) -> Set<ParticipantID> {
        Set(
            entries(in: room).filter { $0.type == .removalNoted }
                .compactMap { note($0, opening($0)) }
                .filter { $0.removal == removal }
                .map(\.entry.author))
    }

    private func note(_ entry: RenderedEntry, _ payload: Payload?) -> Note? {
        guard payload?.type == .removalNoted, let body = try? payload?.decode(RemovalNotedBody.self) else { return nil }
        return Note(entry: entry, removal: body.removal, storedAt: body.storedAt)
    }

    private func claim(_ entry: RenderedEntry, _ payload: Payload?) -> Claim? {
        switch payload?.type {
        case .removal?:
            guard let body = try? payload?.decode(RemovalBody.self) else { return nil }
            return Claim(entry: entry, subject: body.removed, line: chains.line(through: body.heads))
        case .departure?:
            guard let body = try? payload?.decode(DepartureBody.self) else { return nil }
            return Claim(entry: entry, subject: entry.author, line: chains.line(through: body.heads))
        default:
            return nil
        }
    }

    private func walk(_ room: RoomID, claims: [Claim], cutting: Set<Int>, payloads: [EntryHash: Payload]) -> Walk {
        var walked = Walk(standing: Standing(roster: RoomRoster(room: room)))
        var readmitted: [Int: RenderedEntry] = [:]
        let claimAt = Dictionary(uniqueKeysWithValues: claims.indices.map { (claims[$0].entry.id, $0) })

        for entry in entries(in: room) {
            let own = claimAt[entry.id]
            let payload = payloads[entry.id]
            let cutters = cutting.filter { index in
                claims[index].cuts(entry)
                    && !(readmitted[index].map { Self.isAfterReadmission(entry, $0) } ?? false)
            }
            if !cutters.isEmpty {
                walked.standing.out.insert(entry.id)
                if let own { walked.voidedBy[own] = cutters }
                continue
            }
            guard let payload else { continue }
            let absent = walked.standing.roster.absent
            walked.standing.roster.apply(entry, body: payload)
            let now = walked.standing.roster.absent
            if let own, now.contains(claims[own].subject), !absent.contains(claims[own].subject) {
                walked.took.insert(own)
            }
            for index in walked.took where readmitted[index] == nil {
                let subject = claims[index].subject
                if absent.contains(subject), !now.contains(subject) { readmitted[index] = entry }
            }
        }
        return walked
    }

    static func isAfterReadmission(_ entry: RenderedEntry, _ readmitted: RenderedEntry) -> Bool {
        guard readmitted.seq > 0, entry.seq > 0 else { return false }
        return entry.clock[readmitted.feedKey] >= readmitted.seq
            && readmitted.clock[entry.feedKey] < entry.seq
    }

    public func outOfRoom(in room: RoomID, opening: (RenderedEntry) -> Payload?) -> Set<EntryHash> {
        standing(in: room, opening: opening).out
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
