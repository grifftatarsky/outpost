import CarpenterKit
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
        let name = Diagnostics.fingerprint(id.rawValue.uuidString)
        let downloaded: Data?
        do {
            downloaded = try await downloadCopy(of: id, from: author, through: mailbox)
        } catch {
            attachmentRetryAfter[id] = clock.now.addingTimeInterval(Self.attachmentRetryInterval)
            Diagnostics.sync.error(
                "media: could not fetch \(name, privacy: .public) (\(String(describing: error), privacy: .public))")
            throw error
        }
        guard let downloaded else {
            Diagnostics.sync.notice("media: no outbox holds \(name, privacy: .public) any more")
            return nil
        }
        let bytes: Data
        do {
            bytes = try openCopy(downloaded, of: id, matching: digest, from: author)
        } catch {
            Diagnostics.sync.error(
                "media: \(name, privacy: .public) downloaded but does not match the entry's digest; not kept")
            throw error
        }
        try await storage.media.store(bytes, for: id)
        Diagnostics.sync.notice(
            "media: fetched \(name, privacy: .public) bytes=\(bytes.count, privacy: .public)")

        await signFor(id, from: author, through: mailbox)
        return bytes
    }

    private static let attachmentRetryInterval: TimeInterval = 30

    static let attachmentKeptFor = SyncSession.packetWaitsFor

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
        await acknowledge(attachment: id, from: author, with: receipt, through: mailbox)
    }

    private func acknowledge(
        attachment id: AttachmentID, from sender: ParticipantID, with receipt: SealedReceipt,
        through mailbox: any MediaMailbox
    ) async {
        do {
            guard let copy = photoCopyName(of: id, for: sender), let device = enrolment?.device.id else {
                throw MailboxError.unknownPeer
            }
            try await mailbox.acknowledge(
                copy: copy, from: sender, with: receipt, by: device, in: try currentPairs())
            attachmentAcknowledgementsOwed[id] = nil
        } catch {
            attachmentAcknowledgementsOwed[id] = OwedPhotoReceipt(receipt: receipt, sender: sender)
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
        let stored: [AttachmentID: [StoredPhotoCopy]]
        do {
            stored = copiesByPhoto(try await mailbox.storedCopies(in: try currentPairs())).named
        } catch {
            Diagnostics.sync.error(
                "media: could not read the outbox to see who has collected what (\(String(describing: error), privacy: .public))")
            return
        }
        let byPerson = Dictionary(peers().map { ($0.them, $0) }, uniquingKeysWith: { first, _ in first })
        var cleared = 0
        var putBack = 0
        for id in Array(persisted.attachmentsSent.keys) where !uploading.contains(id) {
            guard var record = persisted.attachmentsSent[id] else { continue }
            let copies = stored[id] ?? []
            var owed: Set<ParticipantID> = []
            for person in record.people {
                guard byPerson[person] != nil, let registry = replica.registry(for: person) else {
                    owed.insert(person)
                    continue
                }
                let ways = secrets(with: person)
                for receipt in copies.filter({ $0.to == person }).flatMap(\.receipts) {
                    for secret in ways {
                        guard let signed = AttachmentReceipt.open(
                            receipt, for: id, from: person, with: secret, by: registry)
                        else { continue }
                        record.collectedBy.insert(signed.device)
                        break
                    }
                }
                if !registry.activeDevices.isSubset(of: record.collectedBy) { owed.insert(person) }
            }
            persisted.attachmentsSent[id] = record

            let everybody = owed.isEmpty
            let expired = clock.now.timeIntervalSince(record.sentAt) > Self.attachmentKeptFor
            if everybody || expired {
                if !copies.isEmpty {
                    do { try await mailbox.delete(copies: Set(copies.map(\.name)), in: try currentPairs()) } catch {
                        Diagnostics.sync.error(
                            "media: could not clear a collected attachment (\(String(describing: error), privacy: .public))")
                        continue
                    }
                }
                if persisted.attachmentsSent[id]?.people == record.people { persisted.attachmentsSent[id] = nil }
                cleared += 1
                continue
            }
            let recipients = addressed(
                to: owed.filter { person in !copies.contains { $0.to == person } }.compactMap { byPerson[$0] })
            guard !recipients.isEmpty else { continue }
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
            do {
                try await uploadCopies(
                    of: OutgoingAttachment(id: id, ciphertext: ciphertext, recipients: recipients), through: mailbox)
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

    func notePhotosOwed(_ entries: [Entry]) {
        for entry in entries where entry.author != enrolment?.identity.id {
            persisted.photosOwed.insert(entry.hash)
        }
    }

    func collectAttachments(
        from arrived: [Entry], through mailbox: any MediaMailbox
    ) async {
        notePhotosOwed(arrived)
        let held = entriesByHash
        persisted.photosOwed.formIntersection(held.keys)
        for entry in persisted.photosOwed.compactMap({ held[$0] }) {
            guard let chain = chain(sealing: entry), let payload = entry.opened(using: chain) else { continue }
            guard payload.type == .media, let body = try? payload.decode(MediaBody.self),
                !refusesToDraw(from: entry.author)
            else {
                persisted.photosOwed.remove(entry.hash)
                continue
            }
            var everyPiece = true
            for picture in body.all {
                let reference = picture.attachment
                let pieces = reference.parts.map { $0.map { ($0.id, $0.digest) } } ?? [(reference.id, reference.digest)]
                for (id, digest) in pieces {
                    guard !(attachmentRetryAfter[id].map { $0 > clock.now } ?? false) else {
                        everyPiece = false
                        continue
                    }
                    do {
                        _ = try await sealedPiece(id, digest: digest, from: entry.author, through: mailbox)
                    } catch {
                        everyPiece = false
                        break
                    }
                }
            }
            if everyPiece { persisted.photosOwed.remove(entry.hash) }
        }
        for (id, owed) in attachmentAcknowledgementsOwed {
            await acknowledge(attachment: id, from: owed.sender, with: owed.receipt, through: mailbox)
        }
    }

    func sweepAttachments(through mailbox: any MediaMailbox) async {
        guard !sweptAttachments, enrolment != nil else { return }
        sweptAttachments = true
        let stored: (named: [AttachmentID: [StoredPhotoCopy]], unreadable: [StoredPhotoCopy])
        do {
            stored = copiesByPhoto(try await mailbox.storedCopies(in: try currentPairs()))
        } catch {
            sweptAttachments = false
            Diagnostics.sync.error(
                "media: could not read the outbox to sweep it (\(String(describing: error), privacy: .public))")
            return
        }
        persisted.uploadsLeftForOthers.removeAll { stored.named[$0] == nil }
        let referenced = attachmentsThisMemberSent().union(persisted.uploadsLeftForOthers)
        let kept = Set([ownPhotoReference?.id, ownOutpostPhotoReference?.id].compactMap { $0 })
        let settled = clock.now.addingTimeInterval(-MailboxRules.sweepAge)
        let abandoned = clock.now.addingTimeInterval(-2 * Self.attachmentKeptFor)

        var unnamed = stored.unreadable.filter { $0.storedAt < settled }.map(\.name)
        var unwatched: [PhotoCopyName] = []
        for (id, copies) in stored.named where !uploading.contains(id) {
            let waiting = copies.filter { $0.storedAt < settled }
            guard let written = waiting.map(\.modifiedAt).max() else { continue }
            if !referenced.contains(id) {
                unnamed += waiting.map(\.name)
            } else if written < abandoned, !kept.contains(id), persisted.attachmentsSent[id] == nil {
                unwatched += waiting.map(\.name)
            }
        }
        await deleteCopies(unwatched, through: mailbox, because: "no device of this member is looking after them")
        await deleteCopies(unnamed, through: mailbox, because: "no entry names them")
    }

    private func deleteCopies(_ copies: [PhotoCopyName], through mailbox: any MediaMailbox, because reason: String) async {
        guard !copies.isEmpty else { return }
        do {
            try await mailbox.delete(copies: Set(copies), in: try currentPairs())
            Diagnostics.sync.notice(
                "media: cleared \(copies.count, privacy: .public) upload(s) \(reason, privacy: .public)")
        } catch {
            Diagnostics.sync.error(
                "media: could not clear uploads \(reason, privacy: .public) (\(String(describing: error), privacy: .public))")
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

    // MARK: One copy for each person, sealed for that pair

    func photoCopyName(of photo: AttachmentID, for person: ParticipantID) -> PhotoCopyName? {
        legacySecret(with: person).map { PhotoCopyName(of: photo, between: $0) }
    }

    func uploadCopies(of attachment: OutgoingAttachment, through mailbox: any MediaMailbox) async throws {
        let copies = try attachment.copies(between: { legacySecret(with: $0) })
        try await mailbox.upload(copies, in: try currentPairs())
    }

    func downloadCopy(of photo: AttachmentID, from sender: ParticipantID, through mailbox: any MediaMailbox)
        async throws -> Data?
    {
        guard let copy = photoCopyName(of: photo, for: sender) else { throw MailboxError.unknownPeer }
        return try await mailbox.download(copy, of: photo, from: sender, in: try currentPairs())
    }

    func openCopy(_ downloaded: Data, of photo: AttachmentID, matching digest: Data, from sender: ParticipantID) throws
        -> Data
    {
        guard let pair = legacySecret(with: sender) else { throw AttachmentError.digestMismatch }
        return try PhotoCopy.open(downloaded, of: photo, matching: digest, between: pair)
    }

    func deleteEveryCopy(of photos: [AttachmentID], through mailbox: any MediaMailbox) async throws {
        let me = enrolment?.identity.id
        let pairs = replica.knownParticipants.filter { $0 != me }.compactMap { legacySecret(with: $0) }
        let copies = Set(photos.flatMap { photo in pairs.map { PhotoCopyName(of: photo, between: $0) } })
        guard !copies.isEmpty else { return }
        try await mailbox.delete(copies: copies, in: try currentPairs())
    }

    func copiesByPhoto(_ copies: [StoredPhotoCopy]) -> (
        named: [AttachmentID: [StoredPhotoCopy]], unreadable: [StoredPhotoCopy]
    ) {
        var pairs: [ParticipantID: PairwiseSecret] = [:]
        var named: [AttachmentID: [StoredPhotoCopy]] = [:]
        var unreadable: [StoredPhotoCopy] = []
        for copy in copies {
            if pairs[copy.to] == nil { pairs[copy.to] = legacySecret(with: copy.to) }
            guard let pair = pairs[copy.to], let label = copy.label,
                let photo = PhotoCopy.photo(labelled: label, named: copy.name, between: pair)
            else {
                unreadable.append(copy)
                continue
            }
            named[photo, default: []].append(copy)
        }
        return (named, unreadable)
    }
}
