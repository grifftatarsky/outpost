import CarpenterKit
import CryptoKit
import Foundation

// MARK: What one sync round does

extension AppSession {
    @discardableResult
    public func sync(
        through mailbox: any Mailbox, media: (any MediaMailbox)? = nil, mode: SyncMode = .full
    ) async throws -> SyncReport {
        guard enrolment != nil else { throw AppSessionError.noIdentity }
        let session = SyncSession(mailbox: mailbox, clock: clock)

        var report = SyncReport()
        var sending: [Entry] = []
        var ringingRooms: Set<RoomID> = []
        if mode == .full {
            let owedGrants = try grantsOwed()
            let owedConfirmations = confirmationsOwed()
            if !owedGrants.isEmpty {
                Diagnostics.sync.notice(
                    "mailbox sync: owe \(owedGrants.count, privacy: .public) epoch key(s) to peers; sending")
            }
            sending = unsentEntries()

            let reachable = peers().count
            if reachable == 0
                || (sending.isEmpty && owedGrants.isEmpty && owedConfirmations.isEmpty)
            {
                let unsent = sending.count
                let owed = owedGrants.count
                Diagnostics.sync.notice(
                    """
                    mailbox sync: writing nothing — peers=\(reachable, privacy: .public) \
                    unsent=\(unsent, privacy: .public) grantsOwed=\(owed, privacy: .public)
                    """)
            }

            ringingRooms = roomsWithUnsentMessages.intersection(Set(sending.compactMap(\.room)))

            let ringingWall = peersToRingForWall(carrying: sending)

            let wishes = wallsToBeToldAbout()
            let sayingWishes = notifyWallsSent == wishes ? nil : wishes

            do {
                report = try await session.send(
                    sending, to: peers(), certificates: knownCertificates(),
                    revocations: persisted.revocations,
                    granting: owedGrants.map { (to: $0.to, grant: $0.grant) }, at: clock.now,
                    ringing: peersToRing(in: ringingRooms) + ringingWall,
                    identities: knownIdentities(), notifyWalls: sayingWishes,
                    confirming: owedConfirmations.map(\.body))
            } catch let refused as MailboxFailure {
                cannotSend = refused
                Diagnostics.sync.error(
                    "mailbox: nothing can be sent — \(String(describing: refused), privacy: .public)")
                refresh()
                throw refused
            }

            if report.packetsWritten > 0 {
                for owed in owedGrants {
                    issuedGrants.insert(
                        owed.receipt)
                }
            }
            if report.packetsWritten > 0, report.sendFailure == nil {
                roomsWithUnsentMessages.subtract(ringingRooms)
                unsentWallPosts.subtract(sending.filter { $0.room == nil }.map(\.hash))
                wallsWrittenOn.removeAll()
                if sayingWishes != nil { notifyWallsSent = wishes }
            }
        }

        for peer in peers() {
            let collected = try await session.collect(as: peer, at: clock.now)

            for (id, reason) in collected.unopened {
                Diagnostics.sync.error(
                    """
                    mailbox: a packet would not open and was left in the sender's outbox \
                    (\(String(describing: reason), privacy: .public))
                    """)
                _ = id
            }
            let (received, settled) = SyncSession.integrate(collected, into: &replica)
            report = report.adding(received)

            for request in received.repairRequests
            where !persisted.repairDuties.contains(where: { $0.request.id == request.id }) {
                persisted.repairDuties.append(RepairDuty(request: request, from: peer.them))
                if request.reason == .recovery,
                    !persisted.restoreAsks.contains(where: { $0.request == request.id })
                {
                    let holding =
                        persisted.preferences.isHoldingHistoryForRestores
                        && !refusesToDraw(from: peer.them)
                    persisted.restoreAsks.append(
                        RestoreAskRecord(
                            request: request.id, from: peer.them, room: request.room,
                            at: clock.now, hold: holding ? .held : .allowed))
                    persisted.restoreAsks.removeFirst(
                        max(0, persisted.restoreAsks.count - RestoreAskRecord.kept))
                    Diagnostics.sync.notice(
                        """
                        recovery: \(Diagnostics.fingerprint(peer.them.rawValue), privacy: .public) \
                        came back and asked for history\
                        \(holding ? "; held until this device's member checks" : "", privacy: .public)
                        """)
                }
            }
            for answer in received.repairAnswers {
                if let index = persisted.repairs.firstIndex(where: { $0.id == answer.request }) {
                    persisted.repairs[index].answers[peer.them] = answer
                }
            }

            if let me = enrolment?.identity.id, let wishes = received.notifyWalls {
                let wants = wishes.contains(me)
                let held = persisted.wantsOutpostBell.contains(peer.them)
                if wants != held {
                    if wants {
                        persisted.wantsOutpostBell.append(peer.them)
                    } else {
                        persisted.wantsOutpostBell.removeAll { $0 == peer.them }
                    }
                }
            }

            for grant in received.grantsReceived {
                try await adopt(grant, from: peer)
            }

            let owed = entriesNotWrittenDown + received.integrated
            if !owed.isEmpty {
                do {
                    try await storage.log.append(owed)
                    entriesNotWrittenDown = []
                } catch {
                    entriesNotWrittenDown = owed
                    integrity.writesFailed += 1
                    Diagnostics.sync.error(
                        """
                        storage: could not write \(owed.count, privacy: .public) arriving \
                        entr(ies) — not acknowledging them, so they are offered again \
                        (\(String(describing: error), privacy: .public))
                        """)
                    throw error
                }
            }

            if mode == .full {
                do {
                    try await session.acknowledge(collected, settled)
                } catch {
                    Diagnostics.sync.error(
                        "mailbox: could not acknowledge a packet: \(String(describing: error), privacy: .public)")
                }
            }
            if settled.count < collected.packets.count {
                let distinct = Dictionary(grouping: report.refusals, by: \.summary)
                    .map { "\($0.key)\($0.value.count > 1 ? " ×\($0.value.count)" : "")" }
                    .sorted()
                Diagnostics.sync.error(
                    """
                    mailbox: \(collected.packets.count - settled.count, privacy: .public) packet(s) \
                    held back — credentials refused \(report.credentialsRejected, privacy: .public), \
                    entries refused \(report.entriesRejected, privacy: .public): \
                    \(distinct.joined(separator: "; "), privacy: .public)
                    """)
            }
        }

        viewMayBeStale = report.entriesRejected > 0 || report.credentialsRejected > 0

        if mode == .full, let media {
            await collectAttachments(from: report.integrated, through: media)
            await settleOutpostMediaOwed(through: media)
            await sweepAttachments(through: media)
        }

        let arrived = clock.now
        for entry in report.integrated {
            arrivalDelays[entry.hash] = arrived.timeIntervalSince(entry.wallTime)
        }

        if let refused = report.cannotSend {
            cannotSend = refused
        } else if report.packetsWritten > 0 {
            cannotSend = nil
        }

        if report.didAnything || !peers().isEmpty {
            let peerCount = peers().count
            let roomCount = rooms.count
            Diagnostics.sync.notice(
                """
                mailbox sync: peers=\(peerCount, privacy: .public) \
                packetsWritten=\(report.packetsWritten, privacy: .public) \
                entriesSent=\(report.entriesSent, privacy: .public) \
                entriesDelivered=\(report.entriesDelivered, privacy: .public) \
                entriesReceived=\(report.entriesReceived, privacy: .public) \
                alreadyHad=\(report.entriesAlreadyPresent, privacy: .public) \
                grantsReceived=\(report.grantsReceived.count, privacy: .public) \
                rooms=\(roomCount, privacy: .public)
                """)
        }

        for refusal in report.refusals where refusal.isFinal {
            guard let feed = refusal.feed, let seq = refusal.seq else { continue }
            persisted.unverifiable.insert(feed, seq)
        }
        if report.entriesRefusedForever > 0 {
            Diagnostics.sync.notice(
                """
                repair: \(report.entriesRefusedForever, privacy: .public) entr(ies) will never \
                verify here — signed outside the window their device was allowed to sign in
                """)
        }

        for room in Set(report.integrated.compactMap(\.room))
        where chains[room].map({ !$0.knownEpochs.contains(.initial) }) ?? false {
            try await unwindEpochs(in: room, bounded: walkStopsShort(in: room))
        }

        persisted.certificates = knownCertificates()
        persisted.knownKeys = knownIdentities()
        persisted.spentEntries = replica.spentEntries

        let writtenEntries = Set(report.written.flatMap(\.entries))
        for entry in sending where writtenEntries.contains(entry.hash) {
            persisted.syncedFrontier.observe(entry.feedKey, seq: entry.seq)
        }

        if mode == .full, let waiting = try? await mailbox.pendingDeliveries() {
            pendingRecipients = waiting
            let stillWaiting = Set(waiting.keys)
            persisted.outstandingPackets = persisted.outstandingPackets.filter {
                stillWaiting.contains($0.key)
            }
        }
        for wrote in report.written {
            persisted.outstandingPackets[wrote.packet] = wrote.entries
        }
        if mode == .full {
            await turnEveryKeyAfterALoss()
            await askEverybodyForWhatWasSaid()
            await repairWhatHasNotFilledItself()
            await runRepairs(session, excluding: writtenEntries)
        }
        if mode == .full { await turnKeysOwedToDepartures() }

        if mode == .full { await relayJoinConfirmations(report.confirmations) }

        if mode == .full { await raiseSoloChecksOwed() }

        if mode == .full { await settleOwedEpochTurns() }

        if mode == .full { await publishCommentTallies() }

        forks = replica.forks
        integrity.forks = replica.forks
        integrity.rejectedFromPeers += report.entriesRejected

        let reachableNow = Set(peers().map(\.them))
        let newlyMet = reachableNow.subtracting(peersLastRound).count
        metSomebodyNew = newlyMet > 0
        if metSomebodyNew {
            Diagnostics.sync.notice(
                "mailbox sync: met \(newlyMet, privacy: .public) new peer(s); going again")
        }
        peersLastRound = reachableNow

        try await saveState()
        refresh()
        return report
    }


    func knownCertificates() -> [DeviceCertificate] {
        replica.knownParticipants.flatMap { replica.registry(for: $0)?.certificates ?? [] }
    }

    func knownIdentities() -> [IdentityPublicKeys] {
        replica.knownParticipants.compactMap { replica.registry(for: $0)?.identity }
    }

    func unsentEntries() -> [Entry] {
        let sent = persisted.syncedFrontier
        return replica.allEntries
            .filter { $0.seq > sent[$0.feedKey] }
            .sorted {
                if $0.author != $1.author { return $0.author.rawValue.lexicographicallyPrecedes($1.author.rawValue) }
                if $0.device != $1.device { return $0.device.rawValue.lexicographicallyPrecedes($1.device.rawValue) }
                return $0.seq < $1.seq
            }
    }
}
