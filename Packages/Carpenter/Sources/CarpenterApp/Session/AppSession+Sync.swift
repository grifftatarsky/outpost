import CarpenterKit
import CryptoKit
import Foundation

// MARK: What one sync round does

extension AppSession {
    @discardableResult
    public func sync(
        through mailbox: any Mailbox, media: (any MediaMailbox)? = nil, mode: SyncMode = .full
    ) async throws -> SyncReport {
        guard enrolment != nil, !thisDeviceWasRemoved else { throw AppSessionError.noIdentity }
        let session = SyncSession(mailbox: mailbox, clock: clock)

        var report = SyncReport()
        var sending: [Entry] = []
        if mode == .full { (report, sending) = try await sendWhatIsOwed(through: session) }

        for peer in peers() {
            try await takeWhatArrived(from: peer, through: session, mode: mode, into: &report)
        }

        update(\.viewMayBeStale, to: report.entriesRejected > 0 || report.credentialsRejected > 0)

        if mode == .full, let media {
            await collectAttachments(from: report.integrated, through: media)
            await settleOutpostMediaOwed(through: media)
            await sweepAttachments(through: media)
        }

        try await recordWhatArrived(report)
        await recordWhatWasSent(report, sending: sending, mailbox: mailbox, mode: mode)
        if mode == .full {
            await doWhatIsOwed(after: report, through: session)
        }

        update(\.forks, to: replica.forks)
        update(\.integrity.forks, to: replica.forks)
        if report.entriesRejected > 0 { integrity.rejectedFromPeers += report.entriesRejected }
        noteWhoIsReachable()

        try await saveState()
        refresh()
        return report
    }

    private func sendWhatIsOwed(through session: SyncSession) async throws -> (report: SyncReport, sending: [Entry]) {
        var report = SyncReport()
        let owedGrants = try grantsOwed()
        let owedConfirmations = confirmationsOwed()
        if !owedGrants.isEmpty {
            Diagnostics.sync.notice(
                "mailbox sync: owe \(owedGrants.count, privacy: .public) epoch key(s) to peers; sending")
        }
        let sending = unsentEntries()

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

        let ringingRooms = roomsWithUnsentMessages.intersection(Set(sending.compactMap(\.room)))

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
            for owed in owedGrants { issuedGrants.insert(owed.receipt) }
        }
        if report.packetsWritten > 0, report.sendFailure == nil {
            roomsWithUnsentMessages.subtract(ringingRooms)
            unsentWallPosts.subtract(sending.filter { $0.room == nil }.map(\.hash))
            wallsWrittenOn.removeAll()
            if sayingWishes != nil { notifyWallsSent = wishes }
        }
        return (report, sending)
    }

    private func takeWhatArrived(
        from peer: Peer, through session: SyncSession, mode: SyncMode, into report: inout SyncReport
    ) async throws {
        let collected = try await session.collect(as: peer, at: clock.now)

        for (_, reason) in collected.unopened {
            Diagnostics.sync.error(
                """
                mailbox: a packet would not open and was left in the sender's outbox \
                (\(String(describing: reason), privacy: .public))
                """)
        }
        let checked = await replica.signatureChecks(
            for: collected.entries, alsoTrusting: collected.certificates)
        var working = replica
        let (received, settled) = SyncSession.integrate(collected, into: &working, checked: checked)
        if working.revision != replica.revision { replica = working }
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
                sendOwnEntries()
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
            let (credentials, entries) = (report.credentialsRejected, report.entriesRejected)
            Diagnostics.sync.error(
                """
                mailbox: \(collected.packets.count - settled.count, privacy: .public) packet(s) \
                held back — credentials refused \(credentials, privacy: .public), \
                entries refused \(entries, privacy: .public): \
                \(distinct.joined(separator: "; "), privacy: .public)
                """)
        }
    }

    private func recordWhatArrived(_ report: SyncReport) async throws {
        let arrived = clock.now
        for entry in report.integrated {
            arrivalDelays[entry.hash] = arrived.timeIntervalSince(entry.wallTime)
        }

        if let refused = report.cannotSend {
            cannotSend = refused
        } else if report.packetsWritten > 0 {
            cannotSend = nil
        }

        if report.didAnything || hasSomebodyToReach {
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

        update(\.persisted.certificates, to: knownCertificates())
        update(\.persisted.knownKeys, to: knownIdentities())
        update(\.persisted.spentEntries, to: replica.spentEntries)
    }

    private func recordWhatWasSent(
        _ report: SyncReport, sending: [Entry], mailbox: any Mailbox, mode: SyncMode
    ) async {
        let writtenEntries = Set(report.written.flatMap(\.entries))
        for entry in sending where writtenEntries.contains(entry.hash) {
            persisted.syncedFrontier.observe(entry.feedKey, seq: entry.seq)
        }

        if mode == .full, let waiting = try? await mailbox.pendingDeliveries() {
            update(\.pendingRecipients, to: waiting)
            let stillWaiting = Set(waiting.keys)
            update(\.persisted.outstandingPackets, to: persisted.outstandingPackets.filter {
                stillWaiting.contains($0.key)
            })
        }
        for wrote in report.written {
            persisted.outstandingPackets[wrote.packet] = wrote.entries
        }
    }

    private func doWhatIsOwed(after report: SyncReport, through session: SyncSession) async {
        await askEverybodyForWhatWasSaid()
        await repairWhatHasNotFilledItself()
        await runRepairs(session, excluding: Set(report.written.flatMap(\.entries)))
        await rotateKeysOwedToDepartures()
        await relayJoinConfirmations(report.confirmations)
        await raiseSoloChecksOwed()
        await settleOwedKeyRotations()
        await publishCommentTallies()
    }

    private func noteWhoIsReachable() {
        let reachableNow = Set(peers().map(\.them))
        let newlyMet = reachableNow.subtracting(peersLastRound).count
        update(\.metSomebodyNew, to: newlyMet > 0)
        if metSomebodyNew {
            Diagnostics.sync.notice(
                "mailbox sync: met \(newlyMet, privacy: .public) new peer(s); going again")
        }
        update(\.peersLastRound, to: reachableNow)

    }

    func knownCertificates() -> [DeviceCertificate] {
        replica.knownParticipants.flatMap { replica.registry(for: $0)?.certificates ?? [] }
            .sorted {
                $0.participant == $1.participant
                    ? $0.device.rawValue.lexicographicallyPrecedes($1.device.rawValue)
                    : $0.participant.rawValue.lexicographicallyPrecedes($1.participant.rawValue)
            }
    }

    func knownIdentities() -> [IdentityPublicKeys] {
        replica.knownParticipants
            .sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
            .compactMap { replica.registry(for: $0)?.identity }
    }

    func unsentEntries() -> [Entry] {
        let sent = persisted.syncedFrontier
        return replica.heldFeeds
            .sorted {
                if $0.author != $1.author { return $0.author.rawValue.lexicographicallyPrecedes($1.author.rawValue) }
                return $0.device.rawValue.lexicographicallyPrecedes($1.device.rawValue)
            }
            .flatMap { replica.entries(in: $0, after: sent[$0]) }
    }
}
