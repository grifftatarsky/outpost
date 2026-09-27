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

            await engine.onIncoming { [weak self] record in
                await self?.take(record)
            }

            if self.enrolment != nil {
                self.sendOwnEntries()
            } else {
                await self.requestApproval(through: engine)
            }
            try? await engine.refresh()
        }
    }

    func requestApproval(through engine: any EntrySync) async {
        guard enrolment == nil, let pendingDevice else { return }
        do {
            try await engine.send([try DeviceRequest(for: pendingDevice).record()], deleting: [])
            Diagnostics.identity.notice("approval: asked this member's other devices to approve this one")
        } catch {
            Diagnostics.identity.error(
                "approval: could not ask for approval: \(String(describing: error), privacy: .public)")
        }
    }

    private func take(_ record: SiblingRecord) async {
        if enrolment == nil {
            if case .approval(let target) = record.name.kind, target == pendingDevice?.id {
                await takeApproval(record)
            }
            return
        }
        guard let enrolment else { return }
        let me = enrolment.device.id
        let writer = record.name.writer
        guard writer != me else { return }
        if case .catchUp(let target) = record.name.kind, target != me { return }
        switch record.name.kind {
        case .request:
            noteRequest(record)
            return
        case .approval:
            return
        case .authority:
            await takeAuthority(record)
            return
        case .state, .mail, .catchUp:
            break
        }

        let feed: SiblingFeed
        do {
            feed = try await record.sealed.openInBackground(
                with: enrolment.identity, from: writer, as: record.name.kind, reading: enrolment.device)
        } catch CryptoError.notSealedForThisDevice {
            Diagnostics.sync.notice(
                "device sync: a record from another of your devices was not sealed for this one")
            return
        } catch {
            integrity.unreadableSiblingFeeds += 1
            Diagnostics.sync.error(
                "device sync: a sibling record would not open (\(Diagnostics.fingerprint(writer.rawValue), privacy: .public))")
            return
        }
        let writerRemoved = isRemoved(writer)
        guard await take(feed, storedAt: record.modified ?? clock.now, fromRemoved: writerRemoved) else { return }

        switch record.name.kind {
        case .state:
            persisted.siblingMail.noteState(
                from: writer, cursors: feed.collected, at: feed.writtenAt ?? clock.now, me: me)
        case .mail(let number):
            persisted.siblingMail.took(mail: number, from: writer)
        case .catchUp:
            persisted.siblingMail.took(catchUpThrough: feed.through ?? 0, from: writer)
        case .request, .approval, .authority:
            break
        }
        persisted.siblingMail.shared(feed.epochs)
        persisted.siblingMail.shared(feed.entries)
        persisted.siblingMail.shared(feed.people)
        for forwarded in feed.forwarded where !writerRemoved {
            guard let secret = pairwiseSecret(with: forwarded.from) else { continue }
            try? await adopt(forwarded.grant, from: Peer(secret: secret, them: forwarded.from, me: enrolment.identity.id))
        }
        await persistOrReport("what this device has collected from your other devices") {
            try await saveState()
        }
        sendOwnEntries()
    }

    func isRemoved(_ device: DeviceID) -> Bool {
        guard let enrolment, let registry = replica.registry(for: enrolment.identity.id) else { return false }
        return registry.standing(of: device)?.revokedAt != nil
    }

    @discardableResult
    private func take(_ feed: SiblingFeed, storedAt: Date, fromRemoved: Bool = false) async -> Bool {
        guard let enrolment else { return false }

        if let member = feed.member, member != enrolment.identity.id {
            integrity.feedsFromOtherMembers += 1
            Diagnostics.sync.error(
                "device sync: ignored a feed belonging to another member (\(Diagnostics.fingerprint(member.rawValue), privacy: .public))")
            return false
        }
        if feed.member == nil {
            Diagnostics.sync.notice("device sync: a feed did not say whose it is; verifying entries")
        }

        if let writtenAt = feed.writtenAt {
            Diagnostics.sync.notice(
                "device sync: feed written \(Int(self.clock.now.timeIntervalSince(writtenAt) * 1000), privacy: .public)ms ago")
        }

        replica.introduce(enrolment.identity.publicKeys)
        for keys in feed.people where keys.participantID != enrolment.identity.id {
            replica.introduce(keys)
            if !persisted.knownKeys.contains(keys) { persisted.knownKeys.append(keys) }
        }
        let certificatesBefore = Set(knownCertificates())
        guard
            await takeAuthority(
                certificates: feed.certificates, revocations: feed.revocations, storedAt: storedAt)
        else { return false }

        let preferences = fromRemoved ? MemberPreferences() : feed.preferences
        let deletedAfterMerge = persisted.preferences.merged(with: preferences).roomsDeleted
        for held in feed.epochs
        where chains[held.room]?.knownEpochs.contains(held.epoch) != true
            && !deletedAfterMerge.contains(held.room)
        {
            if fromRemoved, !persisted.rekeyBeforeWriting.contains(held.room) {
                persisted.rekeyBeforeWriting.insert(held.room)
                Diagnostics.identity.notice(
                    "device sync: took a room key from a removed device; the room gets a new key before anything is written")
            }
            var chain = chains[held.room] ?? EpochChain(room: held.room)
            chain.adopt(EpochSecret(material: held.material), at: held.epoch)
            chains[held.room] = chain

            await persistOrReport("a room key from another of your devices") {
                try await persistEpoch(
                    EpochSecret(material: held.material), at: held.epoch, for: held.room)
            }
        }

        let mergedPreferences = persisted.preferences.merged(with: preferences)
        let preferencesChanged = mergedPreferences != persisted.preferences
        if preferencesChanged {
            persisted.preferences = mergedPreferences
            projectionInputsChanged()
            await persistOrReport("settings from another of your devices") {
                try await saveState()
            }
            await settleDeletedRooms()
            refresh()
        }

        let fromSiblings = feed.entries.filter { $0.device != enrolment.device.id }
        let checked = await replica.signatureChecks(for: fromSiblings)
        var taken: [Entry] = []
        for entry in fromSiblings {
            do {
                _ = try replica.integrate(entry, checked: checked)
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
            return true
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
        return true
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

    private func siblingRecipients(for kind: SiblingRecord.Kind, among active: [DeviceID]) -> [DeviceRecipient] {
        guard let enrolment, let registry = replica.registry(for: enrolment.identity.id) else { return [] }
        let devices: [DeviceID]
        switch kind {
        case .state, .request, .approval, .authority: return []
        case .mail: devices = active
        case .catchUp(let target): devices = [target]
        }
        let recipients = devices.compactMap { device in
            registry.agreementKey(for: device).map { DeviceRecipient(device: device, agreementKey: $0) }
        }
        return recipients.count == devices.count ? recipients : []
    }

    func heldEpochs() -> [HeldEpoch] {
        chains.flatMap { room, chain in
            chain.knownEpochs.compactMap { epoch in
                (try? chain.secret(for: epoch)).map {
                    HeldEpoch(room: room, epoch: epoch, material: $0.material)
                }
            }
        }
    }

    func sendOwnEntries() {
        guard deviceSync != nil, enrolment != nil, !isHeldByICloud else { return }
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
            guard let deviceSync, enrolment != nil else { return }
            await publishAuthority(through: deviceSync)
            guard let enrolment else { return }
            let me = enrolment.device.id
            let now = clock.now
            let held = heldEpochs()
            let people = replica.knownParticipants.compactMap { replica.registry(for: $0)?.identity }
                .sorted { $0.participantID.rawValue.lexicographicallyPrecedes($1.participantID.rawValue) }
            let preferencesDigest = try? SiblingMail.digest(of: persisted.preferences)
            let plan = persisted.siblingMail.plan(
                entries: replica.allEntries, held: held, people: people, preferences: preferencesDigest,
                me: me, revoked: Set(persisted.revocations.map(\.device)), now: now)

            let state = SiblingFeed(
                entries: [], certificates: knownCertificates(), member: enrolment.identity.id,
                collected: persisted.siblingMail.cursors, revocations: persisted.revocations, people: people)
            let digest = try? SiblingMail.digest(of: state, on: now)

            var drafts: [(kind: SiblingRecord.Kind, feed: SiblingFeed)] = []
            if digest == nil || digest != persisted.siblingMail.lastState {
                drafts.append((.state, SiblingFeed(
                    entries: [], certificates: state.certificates, member: state.member, writtenAt: now,
                    collected: state.collected, revocations: state.revocations, people: people)))
            }
            if let mail = plan.mail {
                drafts.append((.mail(mail.number), SiblingFeed(
                    entries: mail.entries, certificates: [], epochs: mail.epochs,
                    member: enrolment.identity.id, writtenAt: now,
                    preferences: mail.carriesPreferences ? persisted.preferences : MemberPreferences(),
                    forwarded: mail.forwarded, people: mail.people)))
            }
            if !plan.catchUpsFor.isEmpty {
                func catchUp(_ entries: [Entry]) -> SiblingFeed {
                    SiblingFeed(
                        entries: entries, certificates: state.certificates, epochs: held,
                        member: enrolment.identity.id, writtenAt: now, preferences: persisted.preferences,
                        through: plan.through, revocations: persisted.revocations, people: people)
                }
                let everything = catchUp(replica.allEntries)
                for target in plan.catchUpsFor {
                    drafts.append((.catchUp(for: target), everything))
                }
            }
            let deleting = plan.deletions.map { SiblingRecord.Name(writer: me, kind: $0) }

            let before = persisted.siblingMail
            do {
                var records: [SiblingRecord] = []
                for draft in drafts {
                    records.append(SiblingRecord(
                        name: SiblingRecord.Name(writer: me, kind: draft.kind),
                        sealed: try await SealedSiblingFeed.sealInBackground(
                            draft.feed, for: enrolment.identity, on: me, as: draft.kind,
                            to: siblingRecipients(for: draft.kind, among: plan.recipients))))
                }
                if !records.isEmpty || !deleting.isEmpty {
                    try await deviceSync.send(records, deleting: deleting)
                }
                persisted.siblingMail.commit(
                    plan, stateWritten: drafts.contains { $0.kind == .state } ? digest : nil)
            } catch {
                Diagnostics.sync.error(
                    "device sync send failed: \(String(describing: error), privacy: .public)")
            }
            if persisted.siblingMail != before {
                await persistOrReport("what this device has sent to your other devices") {
                    try await saveState()
                }
            }
        } while publishAgain
    }
}
