import CarpenterKit
import CryptoKit
import Foundation
import os

// MARK: What one sync round does

extension AppSession {
    @discardableResult
    public func sync(
        through mailbox: any Mailbox, media: (any MediaMailbox)? = nil, mode: SyncMode = .full,
        from people: Set<ParticipantID>? = nil
    ) async throws -> SyncReport {
        guard !storageIsSealed else {
            Diagnostics.sync.notice("round: this phone is locked and what it keeps is sealed; collecting nothing")
            return SyncReport()
        }
        guard enrolment != nil, !thisDeviceWasRemoved else { throw AppSessionError.noIdentity }
        guard !isHeldByICloud else {
            Diagnostics.sync.notice("round: iCloud is holding this device; sending and fetching nothing")
            return SyncReport()
        }
        guard let pairs = pairs() else { throw AppSessionError.noIdentity }
        let session = SyncSession(mailbox: mailbox, pairs: pairs, clock: clock)
        if mode == .full { await pairUp(through: mailbox) }

        var report = SyncReport()
        var firstFailure: (any Error)?
        for peer in everyPeer() where people?.contains(peer.them) ?? true {
            do {
                try await takeWhatArrived(from: peer, through: session, mode: mode, into: &report)
            } catch {
                firstFailure = firstFailure ?? error
            }
        }
        do { try await writeDownOrReport() } catch { firstFailure = firstFailure ?? error }
        guard enrolment != nil, !thisDeviceWasRemoved else { throw AppSessionError.noIdentity }
        if mode == .full {
            update(\.viewMayBeStale, to: refusalWatch.holdsKeys(after: report.refusals, at: clock.now))
            await pairUp(through: mailbox)
            if let sent = try? await mailbox.sentPackets(in: pairs) {
                await settleWhatWasSent(sent, through: mailbox, in: pairs)
            }
        }
        if mode == .full {
            let now = clock.now
            if addressBook.hasExpired(at: now) { await changeAddressBook { $0.forgetExpired(at: now) } }
            await rotateIfARemovalNeverChangedIt()
            await announceAddresses(through: session)
            var sent = SyncReport()
            do {
                sent = try await sendWhatIsOwed(through: session)
            } catch {
                firstFailure = firstFailure ?? error
                sent.cannotSend = error as? MailboxFailure
            }
            report = report.adding(sent)
            report = report.adding(await tellTheRemoved(after: sent, through: session))
        }

        if mode == .full, let media {
            await collectAttachments(through: media)
            await collectOwnPhotos(through: media)
            await settleAttachmentsSent(through: media)
            await settleOutpostMediaOwed(through: media)
            await sweepAttachments(through: media)
            await settlePhotosAsked(through: session, media: media)
        }

        do { try await recordWhatArrived(report) } catch { firstFailure = firstFailure ?? error }
        recordWhatWasSent(report)
        if mode == .full {
            await doWhatIsOwed(after: report, through: session)
        }

        update(\.forks, to: replica.forks)
        update(\.integrity.forks, to: replica.forks)
        if report.entriesRejected > 0 { integrity.rejectedFromPeers += report.entriesRejected }
        noteWhoIsReachable()

        try await saveState()
        refresh()
        if let firstFailure { throw firstFailure }
        return report
    }

    private func sendWhatIsOwed(through session: SyncSession) async throws -> SyncReport {
        var report = SyncReport()
        let owedGrants = try grantsOwed()
        let owedConfirmations = confirmationsOwed()
        if !owedGrants.isEmpty {
            Diagnostics.sync.notice(
                "mailbox sync: owe \(owedGrants.count, privacy: .public) epoch key(s) to peers; sending")
        }
        let fresh = unsentEntries()
        let sending = removalsFirst(fresh + entriesOwedToSomebody(besides: fresh))
        let freshHashes = Set(fresh.map(\.hash))
        let (held, forGood, owedTo) = (heldBack(), heldBackForGood(), persisted.entriesOwed)
        let withholding: @Sendable (Entry, ParticipantID) -> Bool = { entry, person in
            held(entry, person)
                || (!freshHashes.contains(entry.hash) && owedTo[person]?.contains(entry.hash) != true)
        }

        let authority = ownAuthorityDigest()
        if authority != persisted.authorityAnnounced {
            persisted.authorityAnnounced = authority
            persisted.authorityOwed = Set(everyPeer().map(\.them))
        }
        let reachable = peers()
        let announcingTo = reachable.filter { persisted.authorityOwed.contains($0.them) }
        let announcing = !announcingTo.isEmpty

        if reachable.isEmpty
            || (sending.isEmpty && owedGrants.isEmpty && owedConfirmations.isEmpty && !announcing)
        {
            let unsent = sending.count
            let owed = owedGrants.count
            Diagnostics.sync.notice(
                """
                mailbox sync: writing nothing — peers=\(reachable.count, privacy: .public) \
                unsent=\(unsent, privacy: .public) grantsOwed=\(owed, privacy: .public)
                """)
        }

        let ringingRooms = roomsWithUnsentMessages.intersection(Set(sending.compactMap(\.room)))
        var rung: Set<ParticipantID> = []
        let ringing = (peersToRing(in: ringingRooms) + peersToRingForWall(carrying: sending) + announcingTo)
            .filter { rung.insert($0.them).inserted }

        let wishes = wallsToBeToldAbout()
        let sayingWishes = notifyWallsSent == wishes ? nil : wishes

        do {
            report = try await session.send(
                sending, to: membersFirst(reachable, carrying: sending), certificates: knownCertificates(),
                revocations: persisted.revocations,
                granting: owedGrants.map { (to: $0.to, grant: $0.grant) }, at: clock.now,
                ringing: ringing,
                identities: knownIdentities(), notifyWalls: sayingWishes,
                confirming: owedConfirmations.map(\.body), announcing: announcing, withholding: withholding)
        } catch let refused as MailboxFailure {
            cannotSend = refused
            Diagnostics.sync.error(
                "mailbox: nothing can be sent — \(String(describing: refused), privacy: .public)")
            refresh()
            throw refused
        }
        noteWhatIsStillOwed(after: report, sending: sending, fresh: freshHashes, heldBackForGood: forGood)

        for wrote in report.written where !wrote.grants.isEmpty {
            let carried = Set(owedGrants.filter { wrote.grants.contains($0.grant) }.map(\.receipt))
            issuedGrants.formUnion(carried)
            grantsCarried[wrote.packet] = carried
        }
        if report.packetsWritten > 0, report.sendFailure == nil {
            roomsWithUnsentMessages.subtract(ringingRooms)
            unsentWallPosts.subtract(sending.filter { $0.room == nil }.map(\.hash))
            wallsWrittenOn.removeAll()
            if sayingWishes != nil { notifyWallsSent = wishes }
        }
        return report
    }

    private func noteWhatIsStillOwed(
        after report: SyncReport, sending: [Entry], fresh: Set<EntryHash>,
        heldBackForGood forGood: (Entry, ParticipantID) -> Bool
    ) {
        var landed: [ParticipantID: Set<EntryHash>] = [:]
        for wrote in report.written {
            if let person = wrote.to { landed[person, default: []].formUnion(wrote.entries) }
        }
        let before = persisted.entriesOwed
        var owed: [ParticipantID: Set<EntryHash>] = [:]
        var handedOut: Set<EntryHash> = []
        let everyone = Set(everyPeer().map(\.them))
        for person in everyone {
            let theirs = sending.filter { entry in
                (fresh.contains(entry.hash) || before[person]?.contains(entry.hash) == true) && !forGood(entry, person)
            }
            let hashes = Set(theirs.map(\.hash))
            handedOut.formUnion(hashes)
            let still = hashes.subtracting(landed[person] ?? [])
            if !still.isEmpty { owed[person] = still }
        }
        update(\.persisted.entriesOwed, to: owed)
        for entry in sending where fresh.contains(entry.hash) && handedOut.contains(entry.hash) {
            persisted.syncedFrontier.observe(entry.feedKey, seq: entry.seq)
        }
        let told = Set(landed.keys)
        update(\.persisted.authorityOwed, to: persisted.authorityOwed.subtracting(told).intersection(everyone))
    }

    private func takeWhatArrived(
        from peer: Peer, through session: SyncSession, mode: SyncMode, into report: inout SyncReport
    ) async throws {
        let alternates = alternateSecrets(with: peer.them)
        let signedFor = ownMemberSignedFor(from: peer, alternates: alternates)
        let collected = try await session.collect(
            as: peer, alternates: alternates, learned: whenAddressesWereLearned(of: peer.them), at: clock.now,
            alreadyTaken: signedFor)

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
        let (received, settled) = SyncSession.integrate(
            collected, into: &working, checked: checked, sparing: enrolment?.identity.id,
            meeting: whoToMeet(through: peer.them))
        noteNewcomers(received.newcomersMet, from: peer.them)
        let wallKeyOwed = readerLostADevice(from: replica, to: working)
        if working.revision != replica.revision { replica = working }
        if wallKeyOwed, let me = enrolment?.identity.id {
            await persistOrReport("that your Outpost's key has to be rotated") {
                try await oweKeyRotation(in: outpostRoom(for: me))
            }
        }
        entriesNotWrittenDown += received.integrated
        report = report.adding(received)
        integrity.rejectedFromPeers += received.entriesTooLarge
        noteRefusedForever(received.refusals)

        takeRepairRequests(received.repairRequests, from: peer.them)
        takeAsks(received.photoAsks, from: peer.them)
        noticeOldAddresses(collected, from: peer)
        await takeAddresses(received.addresses, from: peer)
        for answer in received.repairAnswers {
            if let index = persisted.repairs.firstIndex(where: { $0.id == answer.request }) {
                persisted.repairs[index].answers[peer.them] = answer
                let named = answer.elsewhere.intersecting(persisted.repairs[index].request.gaps)
                if !named.isEmpty {
                    persisted.saidElsewhere[peer.them] = (persisted.saidElsewhere[peer.them] ?? []).merging(named)
                }
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

        let onArrival = timeClaims(in: received.integrated, readableFrom: received.readableFrom)
        for received in received.grantsReceived {
            try await adopt(received.grant, from: peer, storedAt: received.storedAt)
        }
        try await adoptGrantsThatWaited()
        var timed = onArrival.timed
        if !onArrival.sealed.isEmpty, let keysArrived = received.grantsReceived.map(\.storedAt).max() {
            timed += timeClaims(
                in: onArrival.sealed, readableFrom: received.readableFrom, keysArrivedAt: keysArrived
            ).timed
        }
        await noteRemovals(timed)

        try await writeDownOrReport()

        if mode == .full, let enrolment, !settled.isEmpty, await ownDevicesCanCollectWhatThisOneHolds() {
            let (member, device, secret) = (enrolment.identity.id, enrolment.device, peer.secret)
            let foundUnder = Dictionary(
                collected.packets.map { ($0.id, $0.secret ?? secret) }, uniquingKeysWith: { first, _ in first })
            do {
                try await session.acknowledge(collected, settled) { packet, tag in
                    try PacketReceipt.seal(packet, under: tag, as: member, by: device, to: foundUnder[packet] ?? secret)
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

    private func noteRefusedForever(_ refusals: [SyncReport.Refusal]) {
        for refusal in refusals where refusal.isFinal {
            guard let feed = refusal.feed, let seq = refusal.seq else { continue }
            persisted.unverifiable.insert(feed, seq)
        }
    }

    private func writeDownOrReport() async throws {
        do {
            try await writeDownWhatIsOwed()
        } catch {
            if !storageIsSealed { integrity.writesFailed += 1 }
            Diagnostics.sync.error(
                """
                storage: still holding \(self.entriesNotWrittenDown.count, privacy: .public) entr(ies) and \
                \(self.epochsNotSaved.count, privacy: .public) key(s) that are not on disk — not \
                acknowledging them, so they are offered again \
                (\(String(describing: error), privacy: .public))
                """)
            throw error
        }
    }

    var everythingHeldIsOnDisk: Bool { entriesNotWrittenDown.isEmpty && epochsNotSaved.isEmpty }

    func writeDownWhatIsOwed() async throws {
        guard !everythingHeldIsOnDisk else { return }
        try await saveKeysStillOwed()
        try await oneWriteAtATime { [self] in
            let owed = entriesNotWrittenDown
            guard !owed.isEmpty else { return }
            try await storage.log.append(owed)
            entriesNotWrittenDown.removeFirst(owed.count)
            notePhotosOwed(owed)
        }
        sendOwnEntries()
    }

    private func saveKeysStillOwed() async throws {
        for owed in epochsNotSaved {
            guard let secret = chains[owed.room]?.heldSecrets(at: owed.epoch).first else {
                epochsNotSaved.remove(owed)
                continue
            }
            try await persistEpoch(secret, at: owed.epoch, for: owed.room)
            try await unwindEpochs(in: owed.room, bounded: walkStopsShort(in: owed.room))
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

    private func recordWhatWasSent(_ report: SyncReport) {
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

    func entriesOwedToSomebody(besides fresh: [Entry]) -> [Entry] {
        let owed = persisted.entriesOwed.values.reduce(into: Set<EntryHash>()) { $0.formUnion($1) }
        guard !owed.isEmpty else { return [] }
        let already = Set(fresh.map(\.hash))
        return replica.allEntries.filter { owed.contains($0.hash) && !already.contains($0.hash) }
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

    func ownMemberSignedFor(
        from peer: Peer, alternates: [PairwiseSecret] = []
    ) -> @Sendable (SyncPacket) -> Bool {
        guard let registry = replica.registry(for: peer.me) else { return { _ in false } }
        let (me, secrets) = (peer.me, [peer.secret] + alternates)
        return { packet in
            packet.receipts.contains { receipt in
                secrets.contains { PacketReceipt.open(receipt, for: packet.id, from: me, with: $0, by: registry) != nil }
            }
        }
    }

    static let packetIsOrphanedAfter = SyncSession.packetWaitsFor + SyncSession.tagWindow

    private func withdrawWhatNobodyTracks(
        in sent: [PacketID: SentPacket], besides mine: [PacketID: Set<EntryHash>], through mailbox: any Mailbox,
        in pairs: Pairs
    ) async {
        guard let newest = sent.values.compactMap(\.createdAt).max() else { return }
        let now = min(clock.now, newest)
        let orphaned = sent.filter { packet, record in
            guard mine[packet] == nil, let created = record.createdAt else { return false }
            return now.timeIntervalSince(created) > Self.packetIsOrphanedAfter
        }
        var withdrawn = 0
        for packet in orphaned.keys {
            do {
                try await mailbox.withdraw(packet, in: pairs)
                withdrawn += 1
            } catch {
                Diagnostics.sync.error(
                    "mailbox: could not withdraw a packet no device tracks (\(String(describing: error), privacy: .public))")
            }
        }
        if withdrawn > 0 {
            Diagnostics.sync.notice(
                "mailbox: withdrew \(withdrawn, privacy: .public) packet(s) that no device was tracking and nobody can find")
        }
    }

    private func noteWhetherCollected(
        _ entries: Set<EntryHash>, by person: ParticipantID, collected: Bool, storedAt: Date?
    ) {
        if collected {
            if persisted.notCollected[person]?.isDisjoint(with: entries) == false {
                let left = persisted.notCollected[person, default: []].subtracting(entries)
                persisted.notCollected[person] = left.isEmpty ? nil : left
            }
            guard let storedAt else { return }
            for entry in ownEntries(among: entries, inRoomsWith: person) {
                persisted.collectedAt[person, default: [:]][entry] = min(
                    persisted.collectedAt[person]?[entry] ?? storedAt, storedAt)
            }
            return
        }
        let theirs = ownEntries(among: entries, inRoomsWith: person)
        guard !theirs.isEmpty else { return }
        persisted.notCollected[person, default: []].formUnion(theirs)
    }

    private func oweAgain(whatDecidesWhoIsInAmong entries: Set<EntryHash>, to person: ParticipantID) {
        let deciding = entries.filter { projection.type(of: $0).map(PayloadType.decidesWhoIsIn.contains) ?? false }
        guard !deciding.isEmpty else { return }
        persisted.entriesOwed[person, default: []].formUnion(deciding)
    }

    private func ownEntries(among entries: Set<EntryHash>, inRoomsWith person: ParticipantID) -> Set<EntryHash> {
        guard let me = enrolment?.identity.id else { return [] }
        let held = entriesByHash
        return entries.filter { hash in
            guard let entry = held[hash], entry.author == me, let room = entry.room else { return false }
            return roster(of: room).members.contains(person)
        }
    }

    private func settleWhatWasSent(
        _ sent: [PacketID: SentPacket], through mailbox: any Mailbox, in pairs: Pairs
    ) async {
        let mine = persisted.outstandingPackets
        var waiting: [PacketID: Set<RecipientTag>] = [:]
        var vanished: [PacketID] = []
        let current = SyncSession.window(at: clock.now)
        let reach = SyncSession.windowLookback + 2
        let windows = (current >= reach ? current - reach : 0)...(current + 1)
        var addressedTo: [RecipientTag: Peer] = [:]
        for peer in peers() {
            for secret in [peer.secret] + alternateSecrets(with: peer.them) {
                let way = Peer(secret: secret, them: peer.them, me: peer.me)
                for window in windows where addressedTo[way.outgoingTag(window: window)] == nil {
                    addressedTo[way.outgoingTag(window: window)] = way
                }
            }
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
            let expired = clock.now.timeIntervalSince(created) > SyncSession.packetWaitsFor
            if missing.isEmpty || expired {
                do {
                    try await mailbox.withdraw(packet, in: pairs)
                    let keys = grantsCarried.removeValue(forKey: packet) ?? []
                    if missing.isEmpty {
                        confirmAnnouncement(packet)
                    } else {
                        issuedGrants.subtract(keys)
                        oweAgain(whatDecidesWhoIsInAmong: entries, to: record.to)
                    }
                    persisted.outstandingPackets[packet] = nil
                    persisted.packetsWritten[packet] = nil
                    noteWhetherCollected(
                        entries, by: record.to, collected: missing.isEmpty, storedAt: record.receiptStoredAt)
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
            try? await mailbox.withdraw(packet, in: pairs)
            persisted.outstandingPackets[packet] = nil
            persisted.packetsWritten[packet] = nil
            grantsCarried[packet] = nil
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
            grantsCarried[packet] = nil
        }
        await withdrawWhatNobodyTracks(in: sent, besides: mine, through: mailbox, in: pairs)
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
