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
        guard !isHeldByICloud else {
            Diagnostics.sync.notice("round: iCloud is holding this device; sending and fetching nothing")
            return SyncReport()
        }
        let session = SyncSession(mailbox: mailbox, clock: clock)

        var report = SyncReport()
        var sending: [Entry] = []
        for peer in peers() {
            try await takeWhatArrived(from: peer, through: session, mode: mode, into: &report)
        }
        guard enrolment != nil, !thisDeviceWasRemoved else { throw AppSessionError.noIdentity }
        if mode == .full, let sent = try? await mailbox.sentPackets() {
            await settleWhatWasSent(sent, through: mailbox)
        }
        if mode == .full {
            let sent: SyncReport
            (sent, sending) = try await sendWhatIsOwed(through: session)
            report = report.adding(sent)
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
        let authority = ownAuthorityDigest()
        let announcing = authority != persisted.authorityAnnounced

        let reachable = peers().count
        if reachable == 0
            || (sending.isEmpty && owedGrants.isEmpty && owedConfirmations.isEmpty && !announcing)
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
                ringing: announcing ? peers() : peersToRing(in: ringingRooms) + ringingWall,
                identities: knownIdentities(), notifyWalls: sayingWishes,
                confirming: owedConfirmations.map(\.body), announcing: announcing)
        } catch let refused as MailboxFailure {
            cannotSend = refused
            Diagnostics.sync.error(
                "mailbox: nothing can be sent — \(String(describing: refused), privacy: .public)")
            refresh()
            throw refused
        }

        if report.packetsWritten > 0 {
            for owed in owedGrants { issuedGrants.insert(owed.receipt) }
            if announcing {
                persisted.authorityAnnounced = authority
                Diagnostics.sync.notice("round: told every peer about a change to this member's devices")
            }
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
        let signedFor = ownMemberSignedFor(from: peer)
        let collected = try await session.collect(as: peer, at: clock.now, alreadyTaken: signedFor)

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

        for received in received.grantsReceived {
            try await adopt(received.grant, from: peer, storedAt: received.storedAt)
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

        if mode == .full, let enrolment {
            let (member, device, secret) = (enrolment.identity.id, enrolment.device, peer.secret)
            do {
                try await session.acknowledge(collected, settled) { packet, tag in
                    try PacketReceipt.seal(packet, under: tag, as: member, by: device, to: secret)
                }
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

        if !report.written.isEmpty {
            let resent = Set(report.written.flatMap(\.entries))
            if !persisted.resend.isDisjoint(with: resent) { persisted.resend.subtract(resent) }
        }
        noteWritten(report)
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
        let unsent = replica.heldFeeds
            .sorted {
                if $0.author != $1.author { return $0.author.rawValue.lexicographicallyPrecedes($1.author.rawValue) }
                return $0.device.rawValue.lexicographicallyPrecedes($1.device.rawValue)
            }
            .flatMap { replica.entries(in: $0, after: sent[$0]) }
        guard !persisted.resend.isEmpty else { return unsent }
        let already = Set(unsent.map(\.hash))
        return unsent + replica.allEntries.filter { persisted.resend.contains($0.hash) && !already.contains($0.hash) }
    }

    func noteWritten(_ report: SyncReport) {
        guard !report.written.isEmpty else { return }
        var waiting = pendingRecipients ?? [:]
        for wrote in report.written {
            persisted.outstandingPackets[wrote.packet] = wrote.entries
            persisted.packetsWritten[wrote.packet] = WrittenPacketRecord(recipients: wrote.recipients, digest: wrote.digest)
            waiting[wrote.packet] = wrote.recipients
        }
        update(\.pendingRecipients, to: waiting)
    }

    func ownMemberSignedFor(from peer: Peer) -> @Sendable (SyncPacket) -> Bool {
        guard let registry = replica.registry(for: peer.me) else { return { _ in false } }
        let (me, secret) = (peer.me, peer.secret)
        return { packet in
            packet.receipts.contains { receipt in
                PacketReceipt.open(receipt, for: packet.id, from: me, with: secret, by: registry) != nil
            }
        }
    }

    private func settleWhatWasSent(_ sent: [PacketID: SentPacket], through mailbox: any Mailbox) async {
        let mine = persisted.outstandingPackets
        var waiting: [PacketID: Set<RecipientTag>] = [:]
        var vanished: [PacketID] = []
        let current = SyncSession.window(at: clock.now)
        let reach = SyncSession.windowLookback + 2
        let windows = (current >= reach ? current - reach : 0)...(current + 1)
        var addressedTo: [RecipientTag: Peer] = [:]
        for peer in peers() {
            for window in windows { addressedTo[peer.outgoingTag(window: window)] = peer }
        }
        var altered: [PacketID] = []
        for (packet, entries) in mine {
            guard let record = sent[packet] else {
                vanished.append(packet)
                persisted.resend.formUnion(entries)
                continue
            }
            let written = persisted.packetsWritten[packet]
            if let digest = written?.digest, let now = record.contentDigest, now != digest {
                altered.append(packet)
                persisted.resend.formUnion(entries)
                continue
            }
            let created = record.createdAt ?? clock.now
            var missing: Set<RecipientTag> = []
            for tag in written?.recipients ?? record.recipients {
                guard
                    let peer = addressedTo[tag],
                    let registry = replica.registry(for: peer.them),
                    record.receipts.contains(where: {
                        $0.tag == tag
                            && PacketReceipt.open($0, for: packet, from: peer.them, with: peer.secret, by: registry) != nil
                    })
                else {
                    missing.insert(tag)
                    continue
                }
            }
            let expired = clock.now.timeIntervalSince(created)
                > SyncSession.tagWindow * Double(SyncSession.windowLookback + 2)
            if missing.isEmpty || expired {
                do {
                    try await mailbox.withdraw(packet)
                    persisted.outstandingPackets[packet] = nil
                    persisted.packetsWritten[packet] = nil
                } catch {
                    Diagnostics.sync.error(
                        "mailbox: could not take back a packet everybody has (\(String(describing: error), privacy: .public))")
                    waiting[packet] = missing
                }
            } else {
                waiting[packet] = missing
            }
        }
        for packet in altered {
            try? await mailbox.withdraw(packet)
            persisted.outstandingPackets[packet] = nil
            persisted.packetsWritten[packet] = nil
            waiting[packet] = nil
        }
        if !altered.isEmpty {
            issuedGrants.removeAll()
            Diagnostics.sync.error(
                """
                mailbox: \(altered.count, privacy: .public) packet(s) were changed on the server after this \
                device wrote them; taking them back and sending what they held again
                """)
        }
        for packet in vanished {
            persisted.outstandingPackets[packet] = nil
            persisted.packetsWritten[packet] = nil
        }
        if !vanished.isEmpty {
            issuedGrants.removeAll()
            Diagnostics.sync.error(
                """
                mailbox: \(vanished.count, privacy: .public) packet(s) left the outbox before everybody \
                signed for them; sending what they held again
                """)
        }
        update(\.pendingRecipients, to: waiting)
    }
}
