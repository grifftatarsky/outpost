import CarpenterKit
import CryptoKit
import Foundation

// MARK: This member's own devices, and the feed between them

extension AppSession {
    public func syncDevices(through engine: any EntrySync) {
        deviceSync = engine
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
                await self?.take(sealed, from: device)
            }

            await self.sendOwnEntriesNow()
            try? await engine.refresh()
        }
    }

    private func take(_ sealed: SealedSiblingFeed, from device: DeviceID) async {
        guard let enrolment else { return }
        guard let feed = try? sealed.open(with: enrolment.identity, from: device) else {
            integrity.unreadableSiblingFeeds += 1
            Diagnostics.sync.error(
                "device sync: a sibling record would not open (\(Diagnostics.fingerprint(device.rawValue), privacy: .public))")
            return
        }
        await take(feed)
    }

    private func take(_ feed: SiblingFeed) async {
        guard let enrolment else { return }

        if let member = feed.member, member != enrolment.identity.id {
            integrity.feedsFromOtherMembers += 1
            Diagnostics.sync.error(
                "device sync: ignored a feed belonging to another member (\(Diagnostics.fingerprint(member.rawValue), privacy: .public))")
            return
        }
        if feed.member == nil {
            Diagnostics.sync.notice("device sync: a feed did not say whose it is; verifying entries")
        }

        if let writtenAt = feed.writtenAt {
            Diagnostics.sync.notice(
                "device sync: feed written \(Int(self.clock.now.timeIntervalSince(writtenAt) * 1000), privacy: .public)ms ago")
        }

        replica.introduce(enrolment.identity.publicKeys)
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

        let deletedAfterMerge = persisted.preferences.merged(with: feed.preferences).roomsDeleted
        for held in feed.epochs
        where chains[held.room]?.knownEpochs.contains(held.epoch) != true
            && !deletedAfterMerge.contains(held.room)
        {
            var chain = chains[held.room] ?? EpochChain(room: held.room)
            chain.adopt(EpochSecret(material: held.material), at: held.epoch)
            chains[held.room] = chain

            await persistOrReport("a room key from another of your devices") {
                try await persistEpoch(
                    EpochSecret(material: held.material), at: held.epoch, for: held.room)
            }
        }

        let mergedPreferences = persisted.preferences.merged(with: feed.preferences)
        let preferencesChanged = mergedPreferences != persisted.preferences
        if preferencesChanged {
            persisted.preferences = mergedPreferences
            await persistOrReport("settings from another of your devices") {
                try await saveState()
            }
            await settleDeletedRooms()
            refresh()
        }

        var taken: [Entry] = []
        for entry in feed.entries where entry.device != enrolment.device.id {
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

        persisted.spentEntries = replica.spentEntries
        guard !taken.isEmpty else {
            if Set(knownCertificates()) != certificatesBefore {
                persisted.certificates = knownCertificates()
                await persistOrReport("a certificate for another of your devices") {
                    try await saveState()
                }
                refresh()
            }
            return
        }

        await persistOrReport("history from another of your devices") {
            try await storage.log.append(taken)
        }

        persisted.certificates = knownCertificates()
        await persistOrReport("the certificate that verifies that history") {
            try await saveState()
        }

        refresh()

        if state == .needsProfile, hasOwnName {
            state = .ready
            Diagnostics.identity.notice("sibling history arrived; now ready")
        }

        Diagnostics.sync.notice("took \(taken.count, privacy: .public) entries from another device")
    }

    public func refreshDeviceSync() async {
        guard let deviceSync else { return }
        do {
            try await deviceSync.refresh()
        } catch {
            Diagnostics.sync.error(
                "device sync refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func sendOwnEntriesNow() async {
        guard let deviceSync, let enrolment else { return }

        let mine = replica.allEntries.filter { $0.device == enrolment.device.id }

        do {
            let feed = SiblingFeed(
                entries: mine, certificates: knownCertificates(), epochs: heldEpochs(),
                member: enrolment.identity.id, writtenAt: clock.now,
                preferences: persisted.preferences)
            try await deviceSync.send(
                try SealedSiblingFeed.seal(
                    feed, for: enrolment.identity, on: enrolment.device.id),
                from: enrolment.device.id)
        } catch {
            Diagnostics.sync.error(
                "device sync catch-up failed: \(String(describing: error), privacy: .public)")
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

    func sendOwnEntries() {
        guard deviceSync != nil, enrolment != nil else { return }
        if publishing {
            publishAgain = true
            return
        }
        publishing = true
        Task { await publishOwnEntries() }
    }

    private func publishOwnEntries() async {
        defer { publishing = false }

        repeat {
            publishAgain = false
            guard let deviceSync, let enrolment else { return }

            do {
                let feed = SiblingFeed(
                    entries: replica.allEntries.filter { $0.device == enrolment.device.id },
                    certificates: knownCertificates(), epochs: heldEpochs(),
                    member: enrolment.identity.id, writtenAt: clock.now,
                    preferences: persisted.preferences)
                try await deviceSync.send(
                    try SealedSiblingFeed.seal(
                        feed, for: enrolment.identity, on: enrolment.device.id),
                    from: enrolment.device.id)
            } catch {
                Diagnostics.sync.error(
                    "device sync send failed: \(String(describing: error), privacy: .public)")
            }
        } while publishAgain
    }
}
