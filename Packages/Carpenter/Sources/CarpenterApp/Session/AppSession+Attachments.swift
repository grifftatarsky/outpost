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
        let sealed = try await sealedAttachment(attachment.reference, from: author, through: mailbox)
        return try sealed.map { try SealedAttachment.open($0, with: attachment.reference) }
    }

    public func holdsAttachment(_ id: AttachmentID) async -> Bool {
        (try? await storage.media.sealed(for: id)) != nil
    }

    private func sealedAttachment(
        _ reference: AttachmentReference, from author: ParticipantID,
        through mailbox: any MediaMailbox
    ) async throws -> Data? {
        if let held = try await storage.media.sealed(for: reference.id) { return held }
        if let inFlight = attachmentTasks[reference.id] { return try await inFlight.value }

        let task = Task<Data?, any Error> {
            try await fetchAttachment(reference, from: author, through: mailbox)
        }
        attachmentTasks[reference.id] = task
        defer { attachmentTasks[reference.id] = nil }
        return try await task.value
    }

    private func fetchAttachment(
        _ reference: AttachmentReference, from author: ParticipantID,
        through mailbox: any MediaMailbox
    ) async throws -> Data? {
        let tags = collectionTags(for: author)
        let name = Diagnostics.fingerprint(reference.id.rawValue.uuidString)
        let bytes: Data?
        do {
            bytes = try await mailbox.download(reference.id, hint: tags)
        } catch {
            attachmentRetryAfter[reference.id] = clock.now.addingTimeInterval(Self.attachmentRetryInterval)
            Diagnostics.sync.error(
                "media: could not fetch \(name, privacy: .public) (\(String(describing: error), privacy: .public))")
            throw error
        }
        guard let bytes else {
            Diagnostics.sync.notice("media: no outbox holds \(name, privacy: .public) any more")
            return nil
        }
        guard SealedAttachment.matches(bytes, reference) else {
            Diagnostics.sync.error(
                "media: \(name, privacy: .public) downloaded but does not match the entry's digest; not kept")
            throw AttachmentError.digestMismatch
        }
        try await storage.media.store(bytes, for: reference.id)
        Diagnostics.sync.notice(
            "media: fetched \(name, privacy: .public) bytes=\(bytes.count, privacy: .public)")

        if !tags.isEmpty { await acknowledge(attachment: reference.id, by: tags, through: mailbox) }
        return bytes
    }

    private static let attachmentRetryInterval: TimeInterval = 30

    private func acknowledge(
        attachment id: AttachmentID, by tags: Set<RecipientTag>, through mailbox: any MediaMailbox
    ) async {
        do {
            try await mailbox.acknowledge(attachment: id, by: tags)
            attachmentAcknowledgementsOwed[id] = nil
        } catch {
            attachmentAcknowledgementsOwed[id] = tags
            Diagnostics.sync.error(
                "media: could not acknowledge an attachment; will retry (\(String(describing: error), privacy: .public))")
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
                guard !(attachmentRetryAfter[picture.attachment.id].map { $0 > clock.now } ?? false)
                else { continue }
                do {
                    _ = try await sealedAttachment(
                        picture.attachment, from: entry.author, through: mailbox)
                } catch {
                }
            }
        }
        for (id, tags) in attachmentAcknowledgementsOwed {
            await acknowledge(attachment: id, by: tags, through: mailbox)
        }
    }

    func sweepAttachments(through mailbox: any MediaMailbox) async {
        guard !sweptAttachments, enrolment != nil, !persisted.awaitingOwnRecords,
            deviceSync == nil || siblingsFetched
        else { return }
        sweptAttachments = true
        let waiting: [AttachmentID: Set<RecipientTag>]
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
        var ids: Set<AttachmentID> = []
        for entry in replica.allEntries where entry.author == enrolment.identity.id {
            guard let chain = chain(sealing: entry), let payload = entry.opened(using: chain)
            else { continue }
            switch payload.type {
            case .media:
                if let body = try? payload.decode(MediaBody.self) {
                    for picture in body.all { ids.insert(picture.attachment.id) }
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
