import CarpenterKit
import CryptoKit
import Foundation

// MARK: Approvals and removals count in the order iCloud first stored them

extension AppSession {
    public func noteICloudHold(_ held: Bool) {
        guard isHeldByICloud != held else { return }
        isHeldByICloud = held
        Diagnostics.sync.notice(
            "iCloud \(held ? "is holding this device: nothing is sent" : "let this device in again", privacy: .public)")
    }

    func authorityNow() -> Date {
        let latest = replica.storedTimes.values.max() ?? .distantPast
        return max(clock.now, latest.addingTimeInterval(0.001))
    }

    func storedTime(for digest: Data, claimed: Date) -> Date? {
        persisted.authorityIsLegacy ? claimed : persisted.authorityStored[digest]
    }

    func keepAuthorityTimes() {
        let merged = persisted.authorityStored.merging(replica.storedTimes) { min($0, $1) }
        if merged != persisted.authorityStored { persisted.authorityStored = merged }
        let own = enrolment?.identity.id
        let others = replica.knownRevocations.filter { $0.participant != own }
        let kept = Set(persisted.otherRevocations)
        if !others.allSatisfy(kept.contains) {
            persisted.otherRevocations = kept.union(others)
                .sorted { $0.digest.lexicographicallyPrecedes($1.digest) }
        }
    }

    func recordAuthority() {
        let own = enrolment?.identity.id
        if let own, let registry = replica.registry(for: own) {
            persisted.revocations = registry.knownRevocations.sorted {
                $0.digest.lexicographicallyPrecedes($1.digest)
            }
        }
        persisted.otherRevocations = replica.knownRevocations.filter { $0.participant != own }
            .sorted { $0.digest.lexicographicallyPrecedes($1.digest) }
        persisted.certificates = knownCertificates()
        persisted.authorityStored = replica.storedTimes
        persisted.authorityIsLegacy = false
    }

    func takeAuthority(_ record: SiblingRecord) async {
        guard let enrolment, let created = record.created else { return }
        let event: AuthorityEvent
        do {
            event = try AuthorityEvent(record: record, openedWith: enrolment.identity)
        } catch {
            integrity.unreadableSiblingFeeds += 1
            Diagnostics.identity.error(
                "authority: a record named for an approval or removal did not match what it held")
            return
        }
        switch event {
        case .added(let certificate):
            _ = await takeAuthority(certificates: [certificate], revocations: [], storedAt: created)
        case .removed(let revocation):
            _ = await takeAuthority(certificates: [], revocations: [revocation], storedAt: created)
        }
        await persistOrReport("an approval or removal from another of your devices") {
            try await saveState()
        }
        refresh()
    }

    func takeAuthority(
        certificates: [DeviceCertificate], revocations: [DeviceRevocation], storedAt: Date
    ) async -> Bool {
        guard enrolment != nil else { return false }
        keepUnpublishedAfter(storedAt)
        for certificate in certificates {
            do {
                try replica.admit(certificate, storedAt: storedAt)
            } catch {
                integrity.certificatesRefused += 1
                Diagnostics.sync.error(
                    "device sync: refused a certificate for one of your own devices — entries it signed cannot verify here (\(String(describing: error), privacy: .public))")
            }
        }
        for revocation in revocations {
            do {
                try replica.revoke(revocation, storedAt: storedAt)
            } catch {
                Diagnostics.identity.error(
                    "authority: refused a removal (\(String(describing: error), privacy: .public))")
            }
        }
        recordAuthority()
        if thisDeviceWasRemoved {
            await handOverBeforeErasing()
            await eraseAfterRemoval()
            return false
        }
        return true
    }

    private func handOverBeforeErasing() async {
        guard let enrolment, let deviceSync,
            let registry = replica.registry(for: enrolment.identity.id),
            let standing = registry.standing(of: enrolment.device.id), standing.removedByRecovery,
            let restored = standing.revokedBy, let agreementKey = registry.agreementKey(for: restored)
        else { return }
        let people = replica.knownParticipants.compactMap { replica.registry(for: $0)?.identity }
        let feed = SiblingFeed(
            entries: replica.allEntries.filter { $0.device == enrolment.device.id },
            certificates: knownCertificates(), epochs: heldEpochs(), member: enrolment.identity.id,
            writtenAt: clock.now, revocations: persisted.revocations, people: people)
        do {
            let kind = SiblingRecord.Kind.catchUp(for: restored)
            let record = SiblingRecord(
                name: SiblingRecord.Name(writer: enrolment.device.id, kind: kind),
                sealed: try await SealedSiblingFeed.sealInBackground(
                    feed, for: enrolment.identity, on: enrolment.device.id, as: kind,
                    to: [DeviceRecipient(device: restored, agreementKey: agreementKey)]))
            try await deviceSync.send([record], deleting: [])
            Diagnostics.identity.notice(
                "removal: the recovery key removed this device; left what it wrote for the restored one")
        } catch {
            Diagnostics.identity.error(
                "removal: could not leave what this device wrote for the restored one (\(String(describing: error), privacy: .public))")
        }
    }

    func ownAuthorityDigest() -> Data? {
        guard let enrolment, let registry = replica.registry(for: enrolment.identity.id) else { return nil }
        let digests = (registry.certificates.map(\.digest) + registry.knownRevocations.map(\.digest))
            .sorted { $0.lexicographicallyPrecedes($1) }
        return Data(SHA256.hash(data: digests.reduce(Data(), +)))
    }

    func keepUnpublishedAfter(_ instant: Date) {
        for event in ownAuthorityEvents() where !persisted.authorityPublished.contains(event.digest) {
            guard let at = replica.storedTimes[event.digest], at <= instant else { continue }
            replica.settle(event, storedAt: instant.addingTimeInterval(0.001))
        }
    }

    func ownAuthorityEvents() -> [AuthorityEvent] {
        guard let enrolment, let registry = replica.registry(for: enrolment.identity.id) else { return [] }
        let me = enrolment.device.id
        let added = registry.certificates
            .filter { $0.approvedBy == me || ($0.isRecovery && $0.device == me) }
            .map(AuthorityEvent.added)
        let removed = registry.knownRevocations.filter { $0.revokedBy == me }.map(AuthorityEvent.removed)
        return (added + removed).sorted { $0.digest.lexicographicallyPrecedes($1.digest) }
    }

    func publishAuthority(through deviceSync: any EntrySync) async {
        guard let enrolment else { return }
        let waiting = ownAuthorityEvents().filter { !persisted.authorityPublished.contains($0.digest) }
        guard !waiting.isEmpty else { return }
        let records: [SiblingRecord]
        do {
            records = try waiting.map { try $0.record(sealedFor: enrolment.identity, by: enrolment.device.id) }
        } catch {
            Diagnostics.identity.error("authority: could not seal an approval or removal for iCloud")
            return
        }
        let stored: [SiblingRecord.Name: Date]
        do {
            stored = try await deviceSync.send(records, deleting: [])
        } catch {
            Diagnostics.identity.error(
                "authority: could not store an approval or removal in iCloud: \(String(describing: error), privacy: .public)")
            return
        }
        for (event, record) in zip(waiting, records) {
            guard let at = stored[record.name] else { continue }
            replica.settle(event, storedAt: at)
            persisted.authorityPublished.insert(event.digest)
        }
        recordAuthority()
        persisted.authorityStored = persisted.authorityStored.merging(replica.storedTimes) { $1 }
        await persistOrReport("when iCloud stored this device's approvals and removals") {
            try await saveState()
        }
        Diagnostics.identity.notice(
            "authority: stored \(stored.count, privacy: .public) approval(s) or removal(s) in iCloud")
    }
}
