import CarpenterKit
import CryptoKit
import Foundation

// MARK: Filling a hole in what was said, and the way back to a peer's outbox

extension AppSession {
    // MARK: History repair

    public func missingHistory(in room: ConversationID) -> [FeedGap] {
        replica.gaps(from: membersToCheck(in: room), in: room).subtracting(persisted.unverifiable)
            .subtracting(persisted.elsewhere)
    }

    private func membersToCheck(in room: ConversationID) -> Set<ParticipantID> {
        let roster = roster(of: room)
        return roster.members.union(roster.requests.keys)
    }

    @discardableResult
    public func startRepair(in room: ConversationID, asking: ParticipantID? = nil) async -> HistoryRepairStatus? {
        await beginRepair(in: room, asking: asking, quiet: false)
        return repairStatus(of: room)
    }

    @discardableResult
    private func beginRepair(
        in room: ConversationID, asking: ParticipantID?, quiet: Bool, reason: RepairReason = .gap
    ) async -> Bool {
        guard enrolment != nil else { return false }
        let authors = membersToCheck(in: room)
        let reachable = Set(peers().map(\.them)).intersection(authors)
        let asked = (asking.map { reachable.intersection([$0]) } ?? reachable)
            .sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
        guard !asked.isEmpty else { return false }

        let request = RepairRequest(
            authors: authors.sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) },
            heads: replica.heads(of: authors, in: room),
            gaps: replica.gaps(from: authors, in: room).subtracting(persisted.unverifiable)
                .subtracting(persisted.elsewhere),
            room: room, reason: reason)
        persisted.repairs.removeAll { $0.room == room }
        persisted.repairs.append(
            HistoryRepair(
                id: request.id, room: room, startedAt: clock.now, request: request, asked: asked,
                quiet: quiet))
        do {
            try await saveState()
        } catch {
            Diagnostics.sync.error(
                "repair: could not save the request: \(String(describing: error), privacy: .public)")
        }
        Diagnostics.sync.notice(
            """
            repair: asking \(asked.count, privacy: .public) peer(s) for \
            \(request.namedCount, privacy: .public) named entr(ies) and anything past \
            \(request.heads.keys.count, privacy: .public) head(s)\
            \(quiet ? " (on its own)" : "", privacy: .public)
            """)
        return true
    }

    func turnEveryKeyAfterALoss() async {
        guard persisted.turnsEveryKeyAfterALoss, enrolment != nil else { return }
        let turning = rooms.map(\.id).filter { chains[$0] != nil }
        guard !turning.isEmpty else { return }

        for room in turning {
            do { try await oweEpochTurn(in: room) } catch {
                Diagnostics.sync.error(
                    """
                    recovery: could not note a key turn this room needs \
                    (\(String(describing: error), privacy: .public))
                    """)
            }
        }
        persisted.turnsEveryKeyAfterALoss = false
        Diagnostics.sync.notice(
            "recovery: turning the key in \(turning.count, privacy: .public) room(s) after a loss")
    }

    public var isTurningEveryKeyAfterALoss: Bool { persisted.turnsEveryKeyAfterALoss }

    func askEverybodyForWhatWasSaid() async {
        guard persisted.wantsWhatWasSaid, enrolment != nil else { return }
        let reachable = Set(peers().map(\.them))
        guard !reachable.isEmpty else { return }

        var asked = false
        for room in rooms.map(\.id) {
            if await beginRepair(in: room, asking: nil, quiet: true, reason: .recovery) {
                asked = true
            }
        }
        guard asked else { return }
        persisted.wantsWhatWasSaid = false
        Diagnostics.sync.notice(
            "recovery: asked \(reachable.count, privacy: .public) peer(s) for what was said")
    }

    public static let holeSettlingDelay: TimeInterval = 120

    public static let automaticRepairInterval: TimeInterval = 3600

    public static let repairPatience: TimeInterval = 86_400

    func repairWhatHasNotFilledItself() async {
        guard enrolment != nil else { return }
        var changed = false

        for room in rooms.map(\.id) {
            guard missingHistory(in: room).isEmpty == false else {
                if persisted.holesNoticed.removeValue(forKey: room) != nil { changed = true }
                continue
            }
            let noticed = persisted.holesNoticed[room] ?? clock.now
            if persisted.holesNoticed[room] == nil {
                persisted.holesNoticed[room] = noticed
                changed = true
            }
            guard clock.now.timeIntervalSince(noticed) >= Self.holeSettlingDelay else { continue }
            if let asked = persisted.askedAutomatically[room],
                clock.now.timeIntervalSince(asked) < Self.automaticRepairInterval
            {
                continue
            }
            if let standing = persisted.repairs.first(where: { $0.room == room }) {
                guard standing.quiet else { continue }
                let uncovered = missingHistory(in: room).subtracting(standing.request.gaps)
                guard !uncovered.isEmpty
                    || standing.isStale(at: clock.now, patience: Self.repairPatience)
                else { continue }
            }

            if await beginRepair(in: room, asking: nil, quiet: true) {
                persisted.askedAutomatically[room] = clock.now
                changed = true
            }
        }

        if changed {
            do { try await saveState() } catch {
                Diagnostics.sync.error(
                    "repair: could not save what it has noticed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func askForWall(of owner: ParticipantID) async {
        guard enrolment != nil else { return }
        let wall = outpostRoom(for: owner)
        guard
            !persisted.repairs.contains(where: {
                $0.room == wall && !$0.isStale(at: clock.now, patience: Self.repairPatience)
            })
        else { return }
        persisted.repairs.removeAll { $0.room == wall }

        let request = RepairRequest(
            authors: [], heads: VectorClock(), gaps: [], room: wall)
        persisted.repairs.append(
            HistoryRepair(
                id: request.id, room: wall, startedAt: clock.now, request: request, asked: [owner],
                quiet: true))
        do { try await saveState() } catch {
            Diagnostics.sync.error(
                "repair: could not save a request for an Outpost: \(String(describing: error), privacy: .public)")
        }
        Diagnostics.sync.notice("repair: asking for an Outpost this device was just let into")
    }

    public func dismissRepair(in room: ConversationID) async {
        guard persisted.repairs.contains(where: { $0.room == room && !$0.quiet }) else { return }
        persisted.repairs.removeAll { $0.room == room && !$0.quiet }
        do {
            try await saveState()
        } catch {
            Diagnostics.sync.error(
                "repair: could not save the dismissal: \(String(describing: error), privacy: .public)")
        }
    }

    public func repairStatus(of room: ConversationID) -> HistoryRepairStatus? {
        guard let repair = persisted.repairs.first(where: { $0.room == room && !$0.quiet })
        else { return nil }
        let authors = Set(repair.request.authors)
        let open = replica.gaps(from: authors, in: repair.room).subtracting(persisted.unverifiable)
            .subtracting(persisted.elsewhere)
        let named = open.intersecting(repair.request.gaps)
        let refused = persisted.unverifiable.stillMissing(of: repair.request.gaps)
        let answered = repair.asked.filter { repair.answers[$0] != nil }
        let waiting = repair.asked.filter { repair.answers[$0] == nil }
        let answers = answered.compactMap { repair.answers[$0] }

        let recovered = repair.request.namedCount - named.total - refused

        var shortfall = 0
        var furthest = VectorClock()
        for answer in answers { furthest = furthest.merging(answer.heads) }
        for feed in furthest.keys where authors.contains(feed.author) {
            let held = replica.highestSequence(in: feed) ?? 0
            guard furthest[feed] > held else { continue }
            var count = Int(furthest[feed] - held)
            for gap in persisted.unverifiable where gap.feed == feed {
                for span in gap.spans {
                    let lower = Swift.max(span.lower, held + 1)
                    let upper = Swift.min(span.upper, furthest[feed])
                    if lower <= upper { count -= Int(upper - lower + 1) }
                }
            }
            shortfall += Swift.max(0, count)
        }

        var nobody = 0
        if !answers.isEmpty {
            for gap in named {
                for span in gap.spans {
                    for seq in span.sequences
                    where answers.allSatisfy({ $0.unheld.contains(gap.feed, seq) }) {
                        nobody += 1
                    }
                }
            }
        }
        let stillMissing = named.total + shortfall
        return HistoryRepairStatus(
            id: repair.id, room: room, startedAt: repair.startedAt,
            asked: repair.asked.map(member), answered: answered.map(member),
            waiting: waiting.map(member), recovered: recovered, stillMissing: stillMissing,
            heldByNobodyAsked: nobody,
            sentButNotArrived: answers.isEmpty ? 0 : stillMissing - nobody,
            unverifiable: refused)
    }

    func runRepairs(_ session: SyncSession, excluding justSent: Set<EntryHash>) async {
        var report = SyncReport()
        let byID = Dictionary(uniqueKeysWithValues: peers().map { ($0.them, $0) })

        for repair in persisted.repairs {
            let unsent = repair.asked.filter { !repair.sent.contains($0) }.compactMap { byID[$0] }
            guard !unsent.isEmpty else { continue }
            let authors = Set(repair.request.authors)
            let request = RepairRequest(
                id: repair.request.id, authors: repair.request.authors,
                heads: replica.heads(of: authors, in: repair.request.room),
                gaps: replica.gaps(from: authors, in: repair.request.room)
                    .subtracting(persisted.unverifiable)
                .subtracting(persisted.elsewhere),
                room: repair.request.room, reason: repair.request.reason)
            do {
                let sent = try await session.send(
                    [], to: unsent, at: clock.now,
                    ringing: repair.request.reason == .recovery ? unsent : [],
                    requests: [request])
                if sent.packetsWritten > 0,
                    let index = persisted.repairs.firstIndex(where: { $0.id == repair.id })
                {
                    persisted.repairs[index].sent.formUnion(unsent.map(\.them))
                    persisted.repairs[index].request = request
                }
                report = report.adding(sent)
            } catch {
                Diagnostics.sync.error(
                    "repair: could not ask a peer: \(String(describing: error), privacy: .public)")
            }
        }

        var asked: [Contradiction] = []
        for contradiction in persisted.contradictionAsks {
            guard let peer = byID[contradiction.by] else { continue }
            let request = RepairRequest(
                authors: [contradiction.feed.author], heads: VectorClock(),
                gaps: [FeedGap(feed: contradiction.feed, spans: [SequenceSpan(contradiction.seq, contradiction.seq)])],
                room: contradiction.feed.conversation)
            do {
                let sent = try await session.send([], to: [peer], at: clock.now, requests: [request])
                if sent.packetsWritten > 0 { asked.append(contradiction) }
                report = report.adding(sent)
            } catch {
                Diagnostics.sync.error(
                    "attestation: could not ask a peer for their copy (\(String(describing: error), privacy: .public))")
            }
        }
        if !asked.isEmpty { persisted.contradictionAsks.removeAll { asked.contains($0) } }

        var answered: Set<RepairDuty> = []
        for duty in persisted.repairDuties {
            if duty.request.reason == .recovery, isHoldingBack(duty.from) { continue }
            guard let peer = byID[duty.from] else {
                answered.insert(duty)
                Diagnostics.sync.notice("repair: dropped a request from a peer this device cannot address")
                continue
            }
            let (held, unheld, apart) = replica.fill(duty.request)
            let floor = duty.request.room.flatMap { roster(of: $0).historyFloor(of: duty.from) }
            var withheld = apart
            var entries: [Entry] = []
            for entry in held {
                guard entry.seq <= persisted.syncedFrontier[entry.feedKey],
                    !justSent.contains(entry.hash)
                else { continue }
                if let floor, entry.payload.epoch < floor {
                    withheld.insert(entry.feedKey, entry.seq)
                    continue
                }
                entries.append(entry)
            }
            let answer = RepairAnswer(
                request: duty.request.id, unheld: unheld, elsewhere: withheld,
                heads: replica.heads(inScopeOf: duty.request))
            let needed = peopleTheyMayKnowOf(entries, among: [peer])
            do {
                let sent = try await session.send(
                    entries, to: [peer], certificates: knownCertificates(of: needed),
                    revocations: persisted.revocations.filter { needed.contains($0.participant) },
                    at: clock.now, answers: [answer],
                    identities: knownIdentities(of: needed))
                report = report.adding(sent)
                if sent.sendFailure == nil { answered.insert(duty) }
            } catch {
                Diagnostics.sync.error(
                    "repair: could not answer a peer: \(String(describing: error), privacy: .public)")
            }
        }
        if !answered.isEmpty {
            persisted.repairDuties.removeAll { answered.contains($0) }
        }
        persisted.repairs.removeAll {
            $0.quiet && ($0.isAnswered || $0.isStale(at: clock.now, patience: Self.repairPatience))
        }
        if report.packetsWritten > 0 {
            Diagnostics.sync.notice(
                """
                repair: wrote \(report.packetsWritten, privacy: .public) packet(s) carrying \
                \(report.entriesSent, privacy: .public) entr(ies); \
                \(answered.count, privacy: .public) request(s) answered
                """)
        }
    }

    func undeliveredEntries() -> Set<EntryHash> {
        var waiting: Set<EntryHash> = []
        for entries in persisted.outstandingPackets.values { waiting.formUnion(entries) }
        return waiting
    }

    func announceOrReport(_ what: String, _ write: () async throws -> Void) async {
        do {
            try await write()
        } catch {
            Diagnostics.sync.error(
                "room: could not write \(what, privacy: .public) — peers will go on seeing what they saw before (\(String(describing: error), privacy: .public))")
        }
    }

    func persistOrReport(_ what: String, _ write: () async throws -> Void) async {
        do {
            try await write()
        } catch {
            integrity.writesFailed += 1
            Diagnostics.sync.error(
                "storage: could not write \(what, privacy: .public) — it is in memory and will be gone on the next launch (\(String(describing: error), privacy: .public))")
        }
    }

    private func openPayload(_ rendered: RenderedEntry) -> Payload? {
        payloadOpener()(rendered)
    }

    // MARK: The reverse channel

    public func shareOffers(of url: URL) -> [ShareOffer] {
        guard enrolment != nil else { return [] }
        let window = SyncSession.window(at: clock.now)

        return peers().compactMap { peer in
            guard let sealed = try? peer.secret.wrap(
                Data(url.absoluteString.utf8), context: PairwiseSecret.shareOfferContext)
            else { return nil }
            return ShareOffer(
                fetchTag: peer.incomingTag(window: window),
                name: peer.secret.shareOfferName(for: peer.them),
                sealed: sealed,
                digest: peer.secret.shareOfferDigest(of: url))
        }
    }

    public func openShareOffers(_ found: [String: Data]) -> [String: URL] {
        guard let me = enrolment?.identity.id, !found.isEmpty else { return [:] }

        var opened: [String: URL] = [:]
        for peer in peers() {
            let name = peer.secret.shareOfferName(for: me)
            guard let sealed = found[name],
                let body = try? peer.secret.unwrap(
                    sealed, context: PairwiseSecret.shareOfferContext),
                let text = String(data: body, encoding: .utf8),
                let url = URL(string: text)
            else { continue }
            opened[name] = url
        }
        return opened
    }
}
