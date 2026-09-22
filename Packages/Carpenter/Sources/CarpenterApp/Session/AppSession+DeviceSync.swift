import CarpenterKit
import CryptoKit
import Foundation

// MARK: This member's own devices, and the records between them

extension AppSession {
    public var isCatchingUp: Bool { persisted.awaitingOwnRecords }

    public func syncDevices(through engine: any EntrySync) {
        deviceSync = engine
        siblingsFetched = false
        deviceSyncGeneration += 1
        let generation = deviceSyncGeneration
        incomingTask?.cancel()

        incomingTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.start()
            } catch {
                Diagnostics.sync.error(
                    "device sync failed to start: \(String(describing: error), privacy: .public)")
                return
            }

            await engine.onIncoming { [weak self] sealed, device in
                await self?.take(sealed, from: device, generation: generation)
            }

            if self.persisted.awaitingOwnRecords {
                await self.learnWhereThisDeviceHadGotTo()
            } else {
                await self.catchUpWithOwnRecords(through: engine)
            }
            if !self.persisted.awaitingOwnRecords { _ = await self.publishOwnRecordsNow() }
            await self.refreshDeviceSync()
        }
    }

    func learnWhereThisDeviceHadGotTo() async {
        guard persisted.awaitingOwnRecords, deviceSync != nil, enrolment != nil else { return }
        // reentrancy considered
        if let learningPlace { return await learningPlace.value }
        let task = Task { await readOwnRecordsBack() }
        learningPlace = task
        await task.value
        learningPlace = nil
    }

    private func readOwnRecordsBack() async {
        guard let deviceSync, let enrolment, persisted.awaitingOwnRecords else { return }
        let device = enrolment.device.id

        let sealed: [SealedSiblingFeed]
        do {
            sealed = try await deviceSync.ownRecords(of: device)
        } catch {
            Diagnostics.sync.error(
                """
                device sync: could not read this device's own records; it writes nothing until it can \
                (\(String(describing: error), privacy: .public))
                """)
            return
        }
        for record in sealed { await take(record, from: device) }

        do {
            try await deviceSync.refresh()
            siblingsFetched = true
        } catch {
            Diagnostics.sync.error(
                """
                device sync: read this device's records but not its siblings', so whether it was \
                removed is not known yet (\(String(describing: error), privacy: .public))
                """)
            return
        }

        if isRevoked(device) {
            await becomeANewDevice()
            return
        }

        persisted.awaitingOwnRecords = false
        await persistOrReport("that this device knows where it had got to") { try await saveState() }
        if state == .ready, !hasOwnName { state = .needsProfile }
        Diagnostics.sync.notice(
            """
            device sync: read back \(sealed.count, privacy: .public) record(s) of this device's own; \
            it knows its place in \(self.heads.count, privacy: .public) conversation(s)
            """)
        refresh()
    }

    private func catchUpWithOwnRecords(through engine: any EntrySync) async {
        guard let device = enrolment?.device.id else { return }
        let before = ownPositions
        do {
            for record in try await engine.ownRecords(of: device) { await take(record, from: device) }
        } catch {
            Diagnostics.sync.error(
                "device sync: could not read this device's own records at start (\(String(describing: error), privacy: .public))")
            return
        }
        let moved = ownPositions.filter { $0.value.seq > before[$0.key]?.seq ?? 0 }.count
        if moved > 0 {
            persisted.ownRecordAhead += moved
            integrity.ownRecordAhead = persisted.ownRecordAhead
            await persistOrReport("that this device's own record was ahead of it") { try await saveState() }
            Diagnostics.sync.error(
                """
                device sync: this device's own record was ahead of it in \(moved, privacy: .public) \
                conversation(s); it moved forward before writing — another copy of this device may be writing
                """)
        }
    }

    private func isRevoked(_ device: DeviceID) -> Bool {
        guard let me = enrolment?.identity.id else { return false }
        return replica.registry(for: me)?.standing(of: device)?.revokedAt != nil
    }

    private func becomeANewDevice() async {
        guard let old = enrolment else { return }
        Diagnostics.identity.notice(
            "enrol: this device was removed from the member's devices; it enrolls again as a new one")
        let store = IdentityStore(keychain: storage.keychain)
        do {
            try await store.forgetDevice()
            let device = DeviceKeys.generate()
            try await store.save(device, for: old.identity.id)
            try replica.admit(
                DeviceCertificate.issue(for: device.publicKey, by: old.identity, at: clock.now))
            enrolment = Enrolment(identity: old.identity, device: device, deviceIsNew: true)
        } catch {
            Diagnostics.identity.error(
                "enrol: could not enroll again after being removed (\(String(describing: error), privacy: .public))")
            return
        }
        persisted.certificates = knownCertificates()
        heads = [:]
        persisted.ownHeads = [:]
        persisted.publishedPositions = [:]
        persisted.awaitingOwnRecords = false
        await persistOrReport("this device's new enrollment") { try await saveState() }
        incomingTask?.cancel()
        deviceSync = nil
        deviceSyncGeneration += 1
        siblingsFetched = false
        refresh()
    }

    private func take(_ sealed: SealedSiblingFeed, from device: DeviceID, generation: Int) async {
        guard generation == deviceSyncGeneration else { return }
        await take(sealed, from: device)
    }

    private func take(_ sealed: SealedSiblingFeed, from device: DeviceID) async {
        guard let enrolment else { return }
        guard let feed = try? sealed.open(with: enrolment.identity, from: device) else {
            integrity.unreadableSiblingFeeds += 1
            Diagnostics.sync.error(
                "device sync: a device record would not open (\(Diagnostics.fingerprint(device.rawValue), privacy: .public))")
            return
        }
        await take(feed, from: device)
    }

    private func take(_ feed: SiblingFeed, from device: DeviceID) async {
        guard let enrolment else { return }
        let isOwn = device == enrolment.device.id

        if let member = feed.member, member != enrolment.identity.id {
            integrity.feedsFromOtherMembers += 1
            Diagnostics.sync.error(
                "device sync: ignored a record belonging to another member (\(Diagnostics.fingerprint(member.rawValue), privacy: .public))")
            return
        }
        if feed.member == nil {
            Diagnostics.sync.notice("device sync: a record did not say whose it is; verifying entries")
        }

        if let writtenAt = feed.writtenAt {
            Diagnostics.sync.notice(
                "device sync: record written \(Int(self.clock.now.timeIntervalSince(writtenAt) * 1000), privacy: .public)ms ago")
        }

        replica.introduce(enrolment.identity.publicKeys)
        let peopleBefore = replica.knownParticipants.count
        for keys in feed.identities { replica.introduce(keys) }
        let certificatesBefore = Set(knownCertificates())
        for certificate in feed.certificates {
            do {
                try replica.admit(certificate)
            } catch {
                integrity.certificatesRefused += 1
                Diagnostics.sync.error(
                    "device sync: refused a certificate for one of your own devices — entries it signed cannot verify here (\(String(describing: error), privacy: .public))")
            }
        }

        var stateChanged =
            Set(knownCertificates()) != certificatesBefore
            || replica.knownParticipants.count != peopleBefore
        for revocation in feed.revocations where !persisted.revocations.contains(revocation) {
            do {
                try replica.revoke(revocation)
                persisted.revocations.append(revocation)
                stateChanged = true
            } catch {
                Diagnostics.sync.error(
                    "device sync: a device's removal would not verify (\(String(describing: error), privacy: .public))")
            }
        }

        let deletedAfterMerge = persisted.preferences.merged(with: feed.preferences).roomsDeleted
        for held in feed.epochs
        where chains[held.room]?.knownEpochs.contains(held.epoch) != true
            && !deletedAfterMerge.contains(held.room)
        {
            var chain = chains[held.room] ?? EpochChain(room: held.room)
            chain.adopt(EpochSecret(material: held.material), at: held.epoch)
            chains[held.room] = chain

            await persistOrReport("a room key from one of your devices") {
                try await persistEpoch(
                    EpochSecret(material: held.material), at: held.epoch, for: held.room)
            }
        }

        let mergedPreferences = persisted.preferences.merged(with: feed.preferences)
        if mergedPreferences != persisted.preferences {
            persisted.preferences = mergedPreferences
            await persistOrReport("settings from one of your devices") {
                try await saveState()
            }
            await settleDeletedRooms()
            refresh()
        }

        for id in feed.uploadsLeftForOthers where !persisted.uploadsLeftForOthers.contains(id) {
            persisted.uploadsLeftForOthers.append(id)
            stateChanged = true
        }
        if !feed.answeredDepartures.isSubset(of: persisted.answeredDepartures) {
            persisted.answeredDepartures.formUnion(feed.answeredDepartures)
            stateChanged = true
        }
        if isOwn, restoreWhatOnlyThisDeviceKept(from: feed) { stateChanged = true }

        var taken: [Entry] = []
        for entry in feed.entries
        where !replica.entries(in: entry.feedKey, at: entry.seq).contains(where: { $0.hash == entry.hash }) {
            do {
                _ = try replica.integrate(entry)
            } catch {
                integrity.unverifiableFromOwnDevices += 1
                Diagnostics.sync.error(
                    "device sync: an entry from one of your own devices did not verify — usually a certificate that has not arrived (\(String(describing: error), privacy: .public))")
                continue
            }
            taken.append(entry)
        }

        adoptOwnHeads(from: taken)
        persisted.spentEntries = replica.spentEntries

        if !taken.isEmpty {
            await persistOrReport("history from one of your devices") {
                try await storage.log.append(taken)
            }
            stateChanged = true
        }
        if stateChanged {
            persisted.certificates = knownCertificates()
            persisted.knownKeys = knownIdentities()
            await persistOrReport("what one of your devices keeps") {
                try await saveState()
            }
            refresh()
        }

        if !taken.isEmpty, state == .needsProfile, hasOwnName {
            state = .ready
            Diagnostics.identity.notice("history from one of your devices arrived; now ready")
        }

        if !taken.isEmpty {
            Diagnostics.sync.notice("took \(taken.count, privacy: .public) entries from one of your devices")
        }
    }

    private func restoreWhatOnlyThisDeviceKept(from feed: SiblingFeed) -> Bool {
        var changed = false
        for (conversation, link) in feed.positions {
            if link.seq > heads[conversation]?.seq ?? 0 {
                heads[conversation] = link
                changed = true
            }
            if link.seq > persisted.ownHeads[conversation]?.seq ?? 0 {
                persisted.ownHeads[conversation] = link
                changed = true
            }
            if link.seq > persisted.publishedPositions[conversation] ?? 0 {
                persisted.publishedPositions[conversation] = link.seq
                changed = true
            }
        }
        for room in feed.greetedRooms where !persisted.greetedRooms.contains(room) {
            persisted.greetedRooms.append(room)
            changed = true
        }
        for (room, mark) in feed.readThrough where persisted.readThrough[room] == nil {
            persisted.readThrough[room] = mark
            changed = true
        }
        if let kept = feed.organisation, organisation == RoomsListOrganisation(), kept != organisation {
            organisation = kept
            persisted.organisation = kept
            changed = true
        }
        return changed
    }

    public func refreshDeviceSync() async {
        guard let deviceSync else { return }
        do {
            try await deviceSync.refresh()
            siblingsFetched = true
        } catch {
            Diagnostics.sync.error(
                "device sync refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func heldEpochs() -> [HeldEpoch] {
        chains.flatMap { room, chain in
            chain.knownEpochs.compactMap { epoch in
                (try? chain.secret(for: epoch)).map {
                    HeldEpoch(room: room, epoch: epoch, material: $0.material)
                }
            }
        }
    }

    var ownPositions: [ConversationID: EntryLink] {
        heads.merging(persisted.ownHeads) { $0.seq >= $1.seq ? $0 : $1 }
    }

    private func ownRecords() -> SiblingFeed? {
        guard let enrolment else { return nil }
        return SiblingFeed(
            entries: replica.allEntries.filter { $0.device == enrolment.device.id },
            certificates: knownCertificates(), epochs: heldEpochs(),
            member: enrolment.identity.id, writtenAt: clock.now,
            preferences: persisted.preferences, positions: ownPositions,
            revocations: persisted.revocations, uploadsLeftForOthers: persisted.uploadsLeftForOthers,
            answeredDepartures: persisted.answeredDepartures, greetedRooms: persisted.greetedRooms,
            readThrough: persisted.readThrough, organisation: organisation,
            identities: knownIdentities())
    }

    var ownRecordIsBehind: Bool {
        guard deviceSync != nil, !persisted.awaitingOwnRecords else { return false }
        return ownPositions.contains { $0.value.seq > persisted.publishedPositions[$0.key] ?? 0 }
    }

    func sendOwnEntries() {
        guard deviceSync != nil, enrolment != nil, !persisted.awaitingOwnRecords else { return }
        if publishing {
            publishAgain = true
            return
        }
        publishing = true
        publishTask = Task { await publishOwnEntries() }
    }

    func publishOwnRecordsNow() async -> Bool {
        if let publishTask { await publishTask.value }
        return await publishOnce()
    }

    private func publishOwnEntries() async {
        defer {
            publishing = false
            publishTask = nil
        }
        repeat {
            publishAgain = false
            _ = await publishOnce()
        } while publishAgain
    }

    private func publishOnce() async -> Bool {
        guard let deviceSync, let enrolment, !persisted.awaitingOwnRecords, let feed = ownRecords()
        else { return false }
        let withEntries = ownEntriesUnpublished
        ownEntriesUnpublished = false
        do {
            let saved = try await deviceSync.send(
                try DeviceRecords.seal(
                    feed, for: enrolment.identity, on: enrolment.device.id, withEntries: withEntries),
                from: enrolment.device.id)
            if withEntries, !saved.entries { ownEntriesUnpublished = true }
            guard saved.summary else { return false }
            let published = feed.positions.mapValues(\.seq)
            guard published != persisted.publishedPositions else { return true }
            persisted.publishedPositions = persisted.publishedPositions.merging(published) { Swift.max($0, $1) }
            await persistOrReport("how far this device's record in iCloud has got") { try await saveState() }
            return true
        } catch {
            if withEntries { ownEntriesUnpublished = true }
            Diagnostics.sync.error(
                "device sync send failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
