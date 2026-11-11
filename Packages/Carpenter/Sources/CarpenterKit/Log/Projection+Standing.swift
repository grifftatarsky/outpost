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
        var line: Set<EntryHash>

        func cuts(_ other: RenderedEntry) -> Bool {
            other.author == subject && other.id != entry.id && !line.contains(other.id)
        }
    }

    private static let namesWhatItSaw: Set<PayloadType> = [.readReceipt, .epochChange, .soloCheck]

    private static func entriesNamed(by payload: Payload) -> [EntryHash] {
        switch payload.type {
        case .readReceipt: (try? payload.decode(ReadReceiptBody.self)).map { [$0.target] } ?? []
        case .epochChange: (try? payload.decode(EpochChangeBody.self))?.heads ?? []
        case .soloCheck: (try? payload.decode(SoloCheckBody.self))?.answering.map { [$0] } ?? []
        default: []
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
        let named: [Claim] = entries(in: room).compactMap { claim($0, payloads[$0.id], in: room, opening: opening) }
        let claims: [Claim] = named.map { keepingAnsweredInvitations(of: $0, in: room, payloads: payloads, besides: named) }
        let notes: [Note] = entries(in: room).compactMap { note($0, payloads[$0.id]) }
        let authors = Dictionary(
            claims.map { ($0.entry.id, $0.entry.author) }, uniquingKeysWith: { first, _ in first })

        let walking = { (cutting: Set<Int>) in self.walk(room, claims: claims, cutting: cutting, payloads: payloads) }

        var cutting = Set(claims.indices)
        while true {
            let walked = walking(cutting)
            let losing = losers(
                among: cutting, after: walked, in: claims, walking: walking,
                noted: { Self.earliest(notes, besides: walked.standing.out, authors: authors) })
            guard !losing.isEmpty else { return withoutWhatStrangersSealed(walked.standing, in: room) }
            cutting.subtract(losing)
        }
    }

    private func losers(
        among cutting: Set<Int>, after walked: Walk, in claims: [Claim], walking: (Set<Int>) -> Walk,
        noted: () -> [EntryHash: Date]
    ) -> Set<Int> {
        let voided = Set(walked.voidedBy.keys).intersection(cutting)
        let free = cutting.subtracting(voided)
        let taking = free.intersection(walked.took)
        let unsettled = free.subtracting(walked.took)
        let voiders = { (claim: Int) in (walked.voidedBy[claim] ?? []).intersection(cutting) }
        func takes(_ claim: Int, _ cutting: Set<Int>) -> Bool { walking(cutting).took.contains(claim) }

        let victims = { (voider: Int) in voided.filter { voiders($0).contains(voider) } }
        let upheld = Set(voided.flatMap(voiders)).intersection(free).filter { voider in
            walked.took.contains(voider) || takes(voider, cutting.subtracting(victims(voider)))
        }
        let answeredAfterTheirRemoval = voided.filter { victim in
            voiders(victim).contains { voider in
                upheld.contains(voider) && Self.hadSeen(claims[voider].entry, before: claims[victim].entry)
            }
        }
        if !answeredAfterTheirRemoval.isEmpty { return answeredAfterTheirRemoval }

        let storedAfterTheirRemoval = voided.filter { victim in
            voiders(victim).contains { voider in
                upheld.contains(voider)
                    && wasStoredFirst(claims[voider].entry, before: claims[victim].entry, noted: noted)
            }
        }
        if !storedAfterTheirRemoval.isEmpty { return storedAfterTheirRemoval }

        if !unsettled.isEmpty {
            let viable = voided.filter { takes($0, cutting.subtracting(voiders($0))) }
            let idle = unsettled.subtracting(walking(taking.union(viable)).took)
            if !idle.isEmpty { return idle }
        }

        let defeated = voided.filter { !voiders($0).isDisjoint(with: upheld) }
        if !defeated.isEmpty { return defeated }

        let undone = unsettled.filter { !takes($0, taking.union([$0])) }
        if !undone.isEmpty { return undone }

        if let first = firstOf(voided, in: claims, noted: noted()) { return voiders(first) }
        return lastOf(unsettled, in: claims, noted: noted()).map { [$0] } ?? []
    }

    private func withoutWhatStrangersSealed(_ standing: Standing, in room: RoomID) -> Standing {
        let known = standing.roster.members.union(standing.roster.absent).union(standing.roster.requests.keys)
        var kept = standing
        for entry in entries(in: room) where entry.content == .sealed && !known.contains(entry.author) {
            kept.out.insert(entry.id)
        }
        return kept
    }

    private func firstOf(_ indices: Set<Int>, in claims: [Claim], noted: [EntryHash: Date]) -> Int? {
        let unpreceded = indices.filter { index in
            !indices.contains { Self.hadSeen(claims[$0].entry, before: claims[index].entry) }
        }
        return (unpreceded.isEmpty ? indices : unpreceded)
            .min { comesFirst(claims[$0].entry, claims[$1].entry, noted: noted) }
    }

    private func lastOf(_ indices: Set<Int>, in claims: [Claim], noted: [EntryHash: Date]) -> Int? {
        let unfollowed = indices.filter { index in
            !indices.contains { Self.hadSeen(claims[index].entry, before: claims[$0].entry) }
        }
        return (unfollowed.isEmpty ? indices : unfollowed)
            .max { comesFirst(claims[$0].entry, claims[$1].entry, noted: noted) }
    }

    private func wasStoredFirst(
        _ removal: RenderedEntry, before answer: RenderedEntry, noted: () -> [EntryHash: Date]
    ) -> Bool {
        guard !Self.hadSeen(answer, before: removal) else { return false }
        if let first = timeThisPhoneSaw(removal, noted: noted), let second = timeThisPhoneSaw(answer, noted: noted),
            first != second
        {
            return first < second
        }
        let written = noted()
        guard let first = written[removal.id], let second = written[answer.id] else { return false }
        return first < second
    }

    private func timeThisPhoneSaw(_ claim: RenderedEntry, noted: () -> [EntryHash: Date]) -> Date? {
        guard claim.author == viewer else { return claimTimes[claim.id] }
        return [claimTimes[claim.id], noted()[claim.id]].compactMap { $0 }.min()
    }

    static func hadSeen(_ earlier: RenderedEntry, before later: RenderedEntry) -> Bool {
        earlier.id != later.id && earlier.seq > 0 && later.clock[earlier.feedKey] >= earlier.seq
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
        var noters: Set<ParticipantID> = []
        for entry in entries(in: room) where entry.type == .removalNoted {
            if note(entry, opening(entry))?.removal == removal { noters.insert(entry.author) }
        }
        return noters
    }

    private func note(_ entry: RenderedEntry, _ payload: Payload?) -> Note? {
        guard payload?.type == .removalNoted, let body = try? payload?.decode(RemovalNotedBody.self) else { return nil }
        return Note(entry: entry, removal: body.removal, storedAt: body.storedAt)
    }

    private func claim(
        _ entry: RenderedEntry, _ payload: Payload?, in room: RoomID, opening: (RenderedEntry) -> Payload?
    ) -> Claim? {
        switch payload?.type {
        case .removal?:
            guard let body = try? payload?.decode(RemovalBody.self) else { return nil }
            let seen = entries(of: body.removed, namedBeforehandBy: entry, in: room, opening: opening)
            return Claim(entry: entry, subject: body.removed, line: chains.line(through: body.heads + seen))
        case .departure?:
            guard let body = try? payload?.decode(DepartureBody.self) else { return nil }
            return Claim(entry: entry, subject: entry.author, line: chains.line(through: body.heads + [entry.id]))
        default:
            return nil
        }
    }

    private func entries(
        of subject: ParticipantID, namedBeforehandBy claim: RenderedEntry, in room: RoomID,
        opening: (RenderedEntry) -> Payload?
    ) -> [EntryHash] {
        var seen: [EntryHash] = []
        for entry in entries(in: room)
        where entry.feedKey == claim.feedKey && entry.seq < claim.seq && Self.namesWhatItSaw.contains(entry.type) {
            guard let payload = opening(entry) else { continue }
            seen += Self.entriesNamed(by: payload).filter { hash in
                positionByID[hash].map { rendered[$0].author == subject } ?? false
            }
        }
        return seen
    }

    private func keepingAnsweredInvitations(
        of claim: Claim, in room: RoomID, payloads: [EntryHash: Payload], besides claims: [Claim]
    ) -> Claim {
        var offered: [Data: (entry: EntryHash, joiner: ParticipantID)] = [:]
        var relayed: [Data: [EntryHash]] = [:]
        var answers: [(invitation: Data, by: RenderedEntry)] = []
        for entry in entries(in: room) {
            guard let payload = payloads[entry.id] else { continue }
            switch payload.type {
            case .joinRequest where entry.author == claim.subject:
                guard let attestation = (try? payload.decode(JoinRequestBody.self))?.attestation else { continue }
                offered[attestation.signature] = (entry.id, attestation.joiner)
            case .joinConfirmed:
                guard let body = try? payload.decode(JoinConfirmedBody.self) else { continue }
                if entry.author == claim.subject {
                    relayed[body.invitation, default: []].append(entry.id)
                } else {
                    answers.append((body.invitation, entry))
                }
            case .admission where entry.author != claim.subject:
                guard let invitation = (try? payload.decode(AdmissionBody.self))?.invitation else { continue }
                answers.append((invitation, entry))
            default:
                continue
            }
        }
        var kept = claim
        for answer in answers {
            guard let offer = offered[answer.invitation], answer.by.author != offer.joiner,
                answer.by.clock[claim.entry.feedKey] < claim.entry.seq,
                !claims.contains(where: { $0.cuts(answer.by) })
            else { continue }
            kept.line.insert(offer.entry)
            kept.line.formUnion(relayed[answer.invitation] ?? [])
        }
        return kept
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

    public func summary(
        of room: RoomID,
        named stored: String?,
        memberCount: Int? = nil,
        others: [ParticipantID] = [],
        unreadFor viewer: ParticipantID? = nil,
        readThrough: EntryHash? = nil,
        undrawn: Set<EntryHash> = [],
        outOfRoom out: Set<EntryHash> = []
    ) -> RoomSummary? {
        guard let stored, foundings[room] != nil, let positions = roomPositions[room] else { return nil }
        let kind = kind(of: room)

        let partner = kind == .solo ? others.first(where: { $0 != self.viewer }).map(member) : nil
        let name = partner?.displayName ?? stored

        let drawn = { (position: Int) in
            !undrawn.contains(self.rendered[position].id) && self.draws(self.rendered[position], notIn: out)
        }
        let last = positions.last { rendered[$0].isConversation && drawn($0) }.map { rendered[$0] }
        let newest = positions.last(where: drawn) ?? positions[0]

        return RoomSummary(
            id: room,
            name: name,
            memberCount: memberCount ?? Set(positions.map { rendered[$0].author }).count,
            lastAuthor: last.map { member($0.author) },
            lastMessage: last.map { preview($0) } ?? "",
            lastActivity: last?.wallTime ?? rendered[newest].wallTime,
            hasUnread: hasUnread(in: room, at: positions, for: viewer, readThrough: readThrough, drawn: drawn),
            isDirect: kind == .solo,
            initials: partner?.initials,
            partner: partner?.id,
            recentSpeakers: kind == .solo ? [] : recentSpeakers(at: positions, drawn: drawn)
        )
    }

    static let speakersShown = 3
    static let speakersSearched = 200

    private func recentSpeakers(at positions: [Int], drawn: (Int) -> Bool) -> [Member] {
        var found: [ParticipantID] = []
        for position in positions.reversed().prefix(Self.speakersSearched) {
            let entry = rendered[position]
            guard entry.isConversation, entry.author != viewer, !found.contains(entry.author), drawn(position)
            else { continue }
            found.append(entry.author)
            if found.count == Self.speakersShown { break }
        }
        return found.map(member)
    }

    private func hasUnread(
        in room: RoomID, at positions: [Int], for viewer: ParticipantID?, readThrough: EntryHash?,
        drawn: (Int) -> Bool
    ) -> Bool {
        guard let viewer else { return false }
        let mark = readThrough.flatMap { positionByID[$0] }
            .flatMap { rendered[$0].isConversation && rendered[$0].room == room ? $0 : nil }
        for position in positions.reversed() {
            if let mark, position <= mark { return false }
            let entry = rendered[position]
            guard entry.isConversation, entry.author != viewer, drawn(position) else { continue }
            if case .withdrawn = entry.content { continue }
            return true
        }
        return false
    }
}
