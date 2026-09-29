import CarpenterKit
import Foundation

// MARK: What a removal changes beyond the log: who is sent a room, and when the removed person hears

extension AppSession {
    func heldBack() -> @Sendable (Entry, ParticipantID) -> Bool {
        let held = entriesByHash
        let projected = projection
        var ends: [ParticipantID: [RoomID: [Entry]]] = [:]
        for room in projected.namedRoomIDs() {
            let roster = roster(of: room)
            for person in roster.absent {
                let end = roster.removal(of: person)?.entry ?? roster.departure(of: person)?.entry
                if let end, let entry = held[end] { ends[person, default: [:]][room, default: []].append(entry) }
            }
        }
        let inside = untold.compactMap { room, told in held[told.entry].map { ($0, roster(of: room).members) } }
        let (knownEnds, knownNotes) = (ends, projected.removalNoteIDs)
        return { entry, person in
            guard !knownNotes.contains(entry.hash) else { return false }
            let outsideTheRoom = inside.contains { removal, members in
                !members.contains(person) && Self.follows(entry, removal)
            }
            if outsideTheRoom { return true }
            guard let room = entry.room, let known = knownEnds[person]?[room] else { return false }
            return known.contains { Self.follows(entry, $0) }
        }
    }

    nonisolated private static func follows(_ entry: Entry, _ end: Entry) -> Bool {
        entry.hash == end.hash || entry.clock[end.feedKey] >= end.seq
    }

    func membersFirst(_ peers: [Peer], carrying entries: [Entry]) -> [Peer] {
        let rooms = Set(entries.compactMap(\.room))
        let members = rooms.reduce(into: Set<ParticipantID>()) { $0.formUnion(roster(of: $1).members) }
        return peers.filter { members.contains($0.them) } + peers.filter { !members.contains($0.them) }
    }

    func removalsFirst(_ entries: [Entry]) -> [Entry] {
        let removals = Set(untold.map { $0.removal.entry })
        guard !removals.isEmpty else { return entries }
        return entries.filter { removals.contains($0.hash) } + entries.filter { !removals.contains($0.hash) }
    }

    var untold: [(room: RoomID, removal: RoomRoster.Removal)] {
        guard let me = enrolment?.identity.id else { return [] }
        return projection.namedRoomIDs().flatMap { room in
            roster(of: room).removals.values
                .filter { $0.by == me && !persisted.removalsTold.contains($0.entry) }
                .map { (room: room, removal: $0) }
        }
    }

    var waitingToBeTold: Set<ParticipantID> {
        Set(untold.map { $0.removal.removed })
    }

    func tellTheRemoved(after sent: SyncReport, through session: SyncSession) async -> SyncReport {
        guard let me = enrolment?.identity.id else { return SyncReport() }
        var report = SyncReport()
        for (room, told) in untold {
            let everyone = Dictionary(uniqueKeysWithValues: everyPeer().map { ($0.them, $0) })
            guard let removal = entriesByHash[told.entry], let removed = everyone[told.removed] else { continue }
            let writable = Set(peers().map(\.them))
            let owed = roster(of: room).members.subtracting([me]).filter { everyone[$0] != nil }
            var holding = Self.holders(of: removal, in: sent)
            let waiting = owed.subtracting(holding).filter { writable.contains($0) }
            if !waiting.isEmpty {
                let again = await writeRemoval(removal, to: waiting.compactMap { everyone[$0] }, through: session)
                report = report.adding(again)
                holding.formUnion(Self.holders(of: removal, in: again))
            }
            let noted = projection.noters(of: told.entry, in: room, opening: payloadOpener())
                .intersection(roster(of: room).members).subtracting([me, told.removed])
            guard !noted.isEmpty || owed.isSubset(of: holding) else { continue }
            let tell = await writeRemoval(removal, to: [removed], through: session)
            report = report.adding(tell)
            if tell.packetsWritten > 0 { persisted.removalsTold.insert(told.entry) }
        }
        return report
    }

    private func writeRemoval(_ removal: Entry, to peers: [Peer], through session: SyncSession) async -> SyncReport {
        do {
            return try await session.send(
                [removal], to: peers, certificates: knownCertificates(), at: clock.now, identities: knownIdentities())
        } catch {
            Diagnostics.sync.error(
                "removal: could not write a removal to the people owed it (\(String(describing: error), privacy: .public))")
            return SyncReport()
        }
    }

    private static func holders(of entry: Entry, in report: SyncReport) -> Set<ParticipantID> {
        Set(report.written.filter { $0.entries.contains(entry.hash) }.compactMap(\.to))
    }

    func takeClaimTimes(_ times: [EntryHash: Date]) {
        let earlier = times.filter { hash, time in persisted.claimTimes[hash].map { time < $0 } ?? true }
        guard !earlier.isEmpty else { return }
        persisted.claimTimes.merge(earlier) { _, sibling in sibling }
        logChanged()
    }

    func timeClaims(
        in entries: [Entry], readableFrom: [EntryHash: Date], keysArrivedAt: Date? = nil
    ) -> (timed: [Entry], sealed: [Entry]) {
        var sealed: [Entry] = []
        var timed: [Entry] = []
        for entry in entries where entry.room != nil && persisted.claimTimes[entry.hash] == nil {
            guard let payload = chain(sealing: entry).flatMap(entry.opened(using:)) else {
                sealed.append(entry)
                continue
            }
            guard Projection.claimTypes.contains(payload.type), let read = readableFrom[entry.hash] else { continue }
            persisted.claimTimes[entry.hash] = max(read, keysArrivedAt ?? read)
            timed.append(entry)
        }
        if !timed.isEmpty { logChanged() }
        return (timed, sealed)
    }

    func noteRemovals(_ timed: [Entry]) async {
        guard let me = enrolment?.identity.id else { return }
        for entry in timed where entry.author != me {
            guard let room = entry.room, let storedAt = persisted.claimTimes[entry.hash],
                let payload = chain(sealing: entry).flatMap(entry.opened(using:)), payload.type == .removal,
                let body = try? payload.decode(RemovalBody.self), body.removed != me,
                roster(of: room).members.contains(me)
            else { continue }
            do {
                try await append(
                    try Payload.removalNoted(entry.hash, storedAt: storedAt), to: room, readableAt: entry.payload.epoch)
            } catch {
                Diagnostics.sync.error(
                    "removal: could not note a removal this phone read (\(String(describing: error), privacy: .public))")
            }
        }
    }
}
