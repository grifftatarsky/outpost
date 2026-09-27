import CarpenterKit
import Foundation

// MARK: Asking for a photo again, and being asked for one

public enum PhotoAskError: Error, Hashable, Sendable {
    case notHeldHere
    case noLongerAsked
}

extension AppSession {
    static let photoAsksKept = 200
    private static let askedFetchInterval: TimeInterval = 60

    // MARK: Asking

    public func canAskAgain(for attachment: AttachmentID, sentBy author: ParticipantID) -> Bool {
        askablePicture(attachment, sentBy: author) != nil
    }

    public func isAskedFor(_ attachment: AttachmentID) -> Bool {
        persisted.photosAsked[attachment] != nil
    }

    @discardableResult
    public func askAgain(for attachment: AttachmentID, sentBy author: ParticipantID) async -> Bool {
        guard let found = askablePicture(attachment, sentBy: author) else { return false }
        persisted.photosAsked[attachment] = AskedPhoto(author: author, entry: found.entry.hash, askedAt: clock.now)
        do { try await saveState() } catch {
            Diagnostics.sync.error(
                "media: could not write down a photo asked for again (\(String(describing: error), privacy: .public))")
        }
        Diagnostics.sync.notice("media: asked the sender for a photo again")
        return true
    }

    private func askablePicture(
        _ attachment: AttachmentID, sentBy author: ParticipantID
    ) -> (entry: Entry, body: MediaBody)? {
        guard let me = enrolment?.identity.id, author != me,
            peers().contains(where: { $0.them == author })
        else { return nil }
        let open = entryOpener()
        for entry in replica.allEntries where entry.author == author {
            guard let room = entry.room, standing(in: room) == .present,
                let payload = open(entry), payload.type == .media,
                let body = try? payload.decode(MediaBody.self),
                let picture = body.all.first(where: { $0.attachment.id == attachment })
            else { continue }
            return (entry, picture)
        }
        return nil
    }

    func settlePhotosAsked(through session: SyncSession, media: any MediaMailbox) async {
        guard !persisted.photosAsked.isEmpty else { return }
        let byPerson = Dictionary(peers().map { ($0.them, $0) }, uniquingKeysWith: { first, _ in first })

        let unsent = persisted.photosAsked.filter { !$0.value.sent }
        for (author, asks) in Dictionary(grouping: unsent, by: \.value.author) {
            guard let peer = byPerson[author] else { continue }
            let asking = asks.map { PhotoAsk(entry: $0.value.entry, attachment: $0.key) }
            do {
                let sent = try await session.send([], to: [peer], at: clock.now, asking: asking)
                noteWritten(sent)
                guard sent.packetsWritten > 0 else { continue }
                for (id, _) in asks { persisted.photosAsked[id]?.sent = true }
            } catch {
                Diagnostics.sync.error(
                    "media: could not send an ask for a photo (\(String(describing: error), privacy: .public))")
            }
        }

        for (id, asked) in persisted.photosAsked where asked.sent {
            guard !(attachmentRetryAfter[id].map { $0 > clock.now } ?? false) else { continue }
            guard let found = askablePicture(id, sentBy: asked.author) else {
                persisted.photosAsked[id] = nil
                continue
            }
            let reference = found.body.attachment
            let pieces = reference.parts.map { $0.map { ($0.id, $0.digest) } } ?? [(reference.id, reference.digest)]
            var held = 0
            for (piece, digest) in pieces {
                guard let bytes = try? await sealedPiece(piece, digest: digest, from: asked.author, through: media),
                    !bytes.isEmpty
                else { break }
                held += 1
            }
            if held == pieces.count {
                persisted.photosAsked[id] = nil
                Diagnostics.sync.notice("media: a photo asked for again has arrived")
            } else {
                attachmentRetryAfter[id] = clock.now.addingTimeInterval(Self.askedFetchInterval)
            }
        }
    }

    // MARK: Being asked

    func takeAsks(_ asks: [PhotoAsk], from person: ParticipantID) {
        for ask in asks where !persisted.photoAsks.contains(where: { $0.from == person && $0.attachment == ask.attachment }) {
            guard let (_, room) = ownPicture(ask.entry, attachment: ask.attachment),
                roster(of: room).members.contains(person)
            else {
                Diagnostics.sync.notice("media: refused an ask for a photo that was not sent to the one asking")
                continue
            }
            persisted.photoAsks.append(
                PhotoAskRecord(from: person, entry: ask.entry, attachment: ask.attachment, at: clock.now))
            persisted.photoAsks.removeFirst(max(0, persisted.photoAsks.count - Self.photoAsksKept))
        }
    }

    private func ownPicture(_ hash: EntryHash, attachment: AttachmentID) -> (body: MediaBody, room: RoomID)? {
        guard let me = enrolment?.identity.id,
            let entry = replica.allEntries.first(where: { $0.hash == hash }),
            entry.author == me, let room = entry.room,
            let payload = entryOpener()(entry), payload.type == .media,
            let body = try? payload.decode(MediaBody.self),
            let picture = body.all.first(where: { $0.attachment.id == attachment })
        else { return nil }
        return (picture, room)
    }

    public func photoRequests(in room: RoomID) -> [PhotoRequest] {
        guard let me = enrolment?.identity.id else { return [] }
        return persisted.photoAsks.compactMap { ask in
            guard let (picture, asked) = ownPicture(ask.entry, attachment: ask.attachment), asked == room,
                roster(of: room).members.contains(ask.from)
            else { return nil }
            return PhotoRequest(
                person: member(ask.from), sender: me, media: MediaAttachment(picture),
                message: MessageID(entry: ask.entry), room: room, askedAt: ask.at)
        }
    }

    public func sendAgain(_ request: PhotoRequest.ID, through mailbox: any MediaMailbox) async throws {
        guard let ask = persisted.photoAsks.first(where: { $0.from == request.person && $0.attachment == request.attachment }),
            let (picture, room) = ownPicture(ask.entry, attachment: ask.attachment),
            roster(of: room).members.contains(ask.from),
            let peer = peers().first(where: { $0.them == ask.from })
        else { throw PhotoAskError.noLongerAsked }

        let ids = picture.attachment.transferIDs
        var sealed: [(AttachmentID, Data)] = []
        for id in ids {
            guard let bytes = try await storage.media.sealed(for: id) else { throw PhotoAskError.notHeldHere }
            sealed.append((id, bytes))
        }
        let tag = peer.outgoingTag(window: SyncSession.window(at: clock.now))
        for (id, bytes) in sealed {
            uploading.insert(id)
            defer { uploading.remove(id) }
            try await mailbox.upload(OutgoingAttachment(id: id, ciphertext: bytes, recipients: [tag]))
        }
        noteAttachmentsSent(ids, to: [ask.from])
        persisted.photoAsks.removeAll { $0.from == ask.from && $0.attachment == ask.attachment }
        await persistOrReport("a photo sent again") { try await saveState() }
        Diagnostics.sync.notice("media: sent a photo again to the one who asked")
    }

    public func dismissPhotoRequest(_ request: PhotoRequest.ID) async {
        persisted.photoAsks.removeAll { $0.from == request.person && $0.attachment == request.attachment }
        do { try await saveState() } catch {
            Diagnostics.sync.error(
                "media: could not write down a dismissed ask (\(String(describing: error), privacy: .public))")
        }
    }
}
