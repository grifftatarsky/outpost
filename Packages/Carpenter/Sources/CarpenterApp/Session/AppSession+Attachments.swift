import CarpenterKit
import CryptoKit
import Foundation

// MARK: Photos and clips, on the way out and on the way back

extension AppSession {
    // MARK: Attachments

    public func attachmentData(
        for attachment: MediaAttachment, sentBy author: ParticipantID,
        through mailbox: any MediaMailbox
    ) async throws -> Data? {
        guard !refusesToDraw(from: author) else { return nil }
        let reference = attachment.reference
        guard reference.parts == nil else { throw AttachmentError.tooLarge }
        let sealed = try await sealedPiece(
            reference.id, digest: reference.digest, from: author, through: mailbox)
        return try sealed.map { try SealedAttachment.open($0, with: reference) }
    }

    public func writeClip(
        for attachment: MediaAttachment, sentBy author: ParticipantID,
        through mailbox: any MediaMailbox, to file: URL
    ) async throws -> Bool {
        guard !refusesToDraw(from: author) else { return false }
        let reference = attachment.reference
        guard reference.parts != nil else {
            guard let data = try await attachmentData(for: attachment, sentBy: author, through: mailbox) else {
                return false
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
            return true
        }
        return try await SealedAttachment.openParts(reference, into: file) { [self] part in
            try await sealedPiece(part.id, digest: part.digest, from: author, through: mailbox)
        }
    }

    public func holdsAttachment(_ id: AttachmentID) async -> Bool {
        (try? await storage.media.sealed(for: id)) != nil
    }

    func sealedPiece(
        _ id: AttachmentID, digest: Data, from author: ParticipantID,
        through mailbox: any MediaMailbox
    ) async throws -> Data? {
        if let held = try await storage.media.sealed(for: id) { return held }
        if let inFlight = attachmentTasks[id] { return try await inFlight.value }

        let task = Task<Data?, any Error> {
            try await fetchPiece(id, digest: digest, from: author, through: mailbox)
        }
        attachmentTasks[id] = task
        defer { attachmentTasks[id] = nil }
        return try await task.value
    }

    private func fetchPiece(
        _ id: AttachmentID, digest: Data, from author: ParticipantID,
        through mailbox: any MediaMailbox
    ) async throws -> Data? {
        let tags = collectionTags(for: author)
        let name = Diagnostics.fingerprint(id.rawValue.uuidString)
        let bytes: Data?
        do {
            bytes = try await mailbox.download(id, hint: tags)
        } catch {
            attachmentRetryAfter[id] = clock.now.addingTimeInterval(Self.attachmentRetryInterval)
            Diagnostics.sync.error(
                "media: could not fetch \(name, privacy: .public) (\(String(describing: error), privacy: .public))")
            throw error
        }
        guard let bytes else {
            Diagnostics.sync.notice("media: no outbox holds \(name, privacy: .public) any more")
            return nil
        }
        guard Data(SHA256.hash(data: bytes)) == digest else {
            Diagnostics.sync.error(
                "media: \(name, privacy: .public) downloaded but does not match the entry's digest; not kept")
            throw AttachmentError.digestMismatch
        }
        try await storage.media.store(bytes, for: id)
        Diagnostics.sync.notice(
            "media: fetched \(name, privacy: .public) bytes=\(bytes.count, privacy: .public)")

        await signFor(id, from: author, through: mailbox)
        return bytes
    }

    private static let attachmentRetryInterval: TimeInterval = 30

    static let attachmentKeptFor = SyncSession.tagWindow * Double(SyncSession.windowLookback + 2)

    private func signFor(_ id: AttachmentID, from author: ParticipantID, through mailbox: any MediaMailbox) async {
        guard let enrolment, let peer = peers().first(where: { $0.them == author }) else { return }
        let receipt: SealedReceipt
        do {
            receipt = try AttachmentReceipt.seal(
                id, under: peer.incomingTag(window: SyncSession.window(at: clock.now)),
                as: enrolment.identity.id, by: enrolment.device, to: peer.secret)
        } catch {
            Diagnostics.sync.error(
                "media: could not sign for an attachment (\(String(describing: error), privacy: .public))")
            return
        }
        await acknowledge(attachment: id, with: receipt, through: mailbox)
    }

    private func acknowledge(
        attachment id: AttachmentID, with receipt: SealedReceipt, through mailbox: any MediaMailbox
    ) async {
        do {
            try await mailbox.acknowledge(attachment: id, with: receipt)
            attachmentAcknowledgementsOwed[id] = nil
        } catch MailboxError.unknownPacket {
            attachmentAcknowledgementsOwed[id] = nil
        } catch {
            attachmentAcknowledgementsOwed[id] = receipt
            Diagnostics.sync.error(
                "media: could not sign for an attachment; will retry (\(String(describing: error), privacy: .public))")
        }
    }

    func recordAttachmentsSent(_ ids: [AttachmentID], to people: Set<ParticipantID>) async {
        noteAttachmentsSent(ids, to: people)
        do { try await saveState() } catch {
            Diagnostics.sync.error(
                "media: could not write down who a photo is for (\(String(describing: error), privacy: .public))")
        }
    }

    func noteAttachmentsSent(_ ids: [AttachmentID], to people: Set<ParticipantID>) {
        let addressed = people.intersection(peers().map(\.them))
        for id in ids {
            var record = persisted.attachmentsSent[id] ?? SentAttachmentRecord(people: [], sentAt: clock.now)
            record.people.formUnion(addressed)
            record.sentAt = clock.now
            persisted.attachmentsSent[id] = record
        }
    }

    func settleAttachmentsSent(through mailbox: any MediaMailbox) async {
        guard enrolment != nil, !persisted.attachmentsSent.isEmpty else { return }
        let stored: [AttachmentID: SentAttachment]
        do {
            stored = try await mailbox.pendingAttachments()
        } catch {
            Diagnostics.sync.error(
                "media: could not read the outbox to see who has collected what (\(String(describing: error), privacy: .public))")
            return
        }
        let byPerson = Dictionary(peers().map { ($0.them, $0) }, uniquingKeysWith: { first, _ in first })
        let window = SyncSession.window(at: clock.now)
        var cleared = 0
        var putBack = 0
        for id in Array(persisted.attachmentsSent.keys) where !uploading.contains(id) {
            guard var record = persisted.attachmentsSent[id] else { continue }
            var owed: Set<ParticipantID> = []
            for person in record.people {
                guard byPerson[person] != nil, let registry = replica.registry(for: person) else {
                    owed.insert(person)
                    continue
                }
                let ways = secrets(with: person)
                for receipt in stored[id]?.receipts ?? [] {
                    for secret in ways {
                        guard let signed = AttachmentReceipt.open(
                            receipt, for: id, from: person, with: secret, by: registry)
                        else { continue }
                        record.collectedBy.insert(signed.device)
                        break
                    }
                }
                if registry.deviceIDs.isDisjoint(with: record.collectedBy) { owed.insert(person) }
            }
            persisted.attachmentsSent[id] = record

            let everybody = owed.isEmpty
            let expired = clock.now.timeIntervalSince(record.sentAt) > Self.attachmentKeptFor
            if everybody || expired {
                if stored[id] != nil {
                    do { try await mailbox.delete(attachment: id) } catch {
                        Diagnostics.sync.error(
                            "media: could not clear a collected attachment (\(String(describing: error), privacy: .public))")
                        continue
                    }
                }
                if persisted.attachmentsSent[id]?.people == record.people { persisted.attachmentsSent[id] = nil }
                cleared += 1
                continue
            }
            guard stored[id] == nil else { continue }
            let ciphertext: Data
            do {
                guard let held = try await storage.media.sealed(for: id) else {
                    persisted.attachmentsSent[id] = nil
                    Diagnostics.sync.error("media: an attachment left the outbox early and this device no longer holds it")
                    continue
                }
                ciphertext = held
            } catch {
                Diagnostics.sync.error(
                    "media: could not read the kept copy of an attachment (\(String(describing: error), privacy: .public))")
                continue
            }
            let tags = Set(owed.compactMap { byPerson[$0]?.outgoingTag(window: window) })
            do {
                try await mailbox.upload(OutgoingAttachment(id: id, ciphertext: ciphertext, recipients: tags))
                putBack += 1
            } catch {
                Diagnostics.sync.error(
                    "media: could not put back an attachment that left the outbox early (\(String(describing: error), privacy: .public))")
            }
        }
        if cleared > 0 || putBack > 0 {
            Diagnostics.sync.notice(
                """
                media: cleared \(cleared, privacy: .public) attachment(s) everybody collected or that waited too long; \
                put back \(putBack, privacy: .public) that left the outbox before everybody had them
                """)
        }
    }

    func collectionTags(for author: ParticipantID) -> Set<RecipientTag> {
        guard let peer = peers().first(where: { $0.them == author }) else { return [] }
        return SyncSession.recentTags(for: peer, at: clock.now)
    }

    func collectAttachments(
        from entries: [Entry], through mailbox: any MediaMailbox
    ) async {
        for entry in entries {
            guard let chain = chain(sealing: entry),
                let payload = entry.opened(using: chain), payload.type == .media,
                let body = try? payload.decode(MediaBody.self),
                !refusesToDraw(from: entry.author)
            else { continue }
            for picture in body.all {
                let reference = picture.attachment
                let pieces = reference.parts.map { $0.map { ($0.id, $0.digest) } } ?? [(reference.id, reference.digest)]
                for (id, digest) in pieces {
                    guard !(attachmentRetryAfter[id].map { $0 > clock.now } ?? false) else { continue }
                    do {
                        _ = try await sealedPiece(id, digest: digest, from: entry.author, through: mailbox)
                    } catch {
                        break
                    }
                }
            }
        }
        for (id, receipt) in attachmentAcknowledgementsOwed {
            await acknowledge(attachment: id, with: receipt, through: mailbox)
        }
    }

    func sweepAttachments(through mailbox: any MediaMailbox) async {
        guard !sweptAttachments, enrolment != nil else { return }
        sweptAttachments = true
        let waiting: [AttachmentID: Date]
        do {
            waiting = try await mailbox.sweepableAttachments()
        } catch {
            sweptAttachments = false
            Diagnostics.sync.error(
                "media: could not read the outbox to sweep it (\(String(describing: error), privacy: .public))")
            return
        }
        var referenced = attachmentsThisMemberSent()
        if !persisted.uploadsLeftForOthers.isEmpty, let stored = try? await mailbox.pendingAttachments() {
            persisted.uploadsLeftForOthers.removeAll { stored[$0] == nil && waiting[$0] == nil }
        }
        referenced.formUnion(persisted.uploadsLeftForOthers)
        let kept = Set([ownPhotoReference?.id, ownOutpostPhotoReference?.id].compactMap { $0 })
        let abandoned = clock.now.addingTimeInterval(-2 * Self.attachmentKeptFor)
        for (id, written) in waiting
        where written < abandoned && referenced.contains(id) && !kept.contains(id)
            && persisted.attachmentsSent[id] == nil && !uploading.contains(id)
        {
            do {
                try await mailbox.delete(attachment: id)
                Diagnostics.sync.notice("media: cleared an attachment no device of this member is looking after")
            } catch {
                Diagnostics.sync.error(
                    "media: could not clear an abandoned attachment (\(String(describing: error), privacy: .public))")
            }
        }
        for id in waiting.keys where !referenced.contains(id) && !uploading.contains(id) {
            do {
                try await mailbox.delete(attachment: id)
                Diagnostics.sync.notice("media: swept an upload no entry names")
            } catch {
                Diagnostics.sync.error(
                    "media: could not sweep an orphaned upload (\(String(describing: error), privacy: .public))")
            }
        }
    }

    private func attachmentsThisMemberSent() -> Set<AttachmentID> {
        guard let enrolment else { return [] }
        let open = entryOpener()
        var ids: Set<AttachmentID> = []
        for entry in replica.allEntries where entry.author == enrolment.identity.id {
            guard let payload = open(entry) else { continue }
            switch payload.type {
            case .media:
                if let body = try? payload.decode(MediaBody.self) {
                    for picture in body.all { ids.formUnion(picture.attachment.transferIDs) }
                }
            case .memberPhoto:
                if let reference = (try? payload.decode(MemberPhotoBody.self))?.reference {
                    ids.insert(reference.id)
                }
            default:
                continue
            }
        }
        return ids
    }
}
