import CarpenterKit
import Foundation

// MARK: Deleting a conversation this member is no longer in

extension AppSession {
    public func deletion(of room: RoomID) -> RoomDeletion {
        guard let enrolment, standing(in: room) != .present else { return .stillIn }
        guard !replica.knownParticipants.contains(where: { outpostRoom(for: $0) == room }) else {
            return .stillIn
        }
        let feed = FeedKey(author: enrolment.identity.id, device: enrolment.device.id)
        let sent = persisted.syncedFrontier[feed]
        let unsent = replica.allEntries.contains { $0.room == room && $0.feedKey == feed && $0.seq > sent }
        return unsent ? .departureNotSent : .allowed
    }

    public func deleteRoom(_ room: RoomID) async throws {
        switch deletion(of: room) {
        case .stillIn: throw MembershipError.stillInTheRoom
        case .departureNotSent: throw MembershipError.departureNotSent
        case .allowed: break
        }

        let answered = persisted.preferences.deletedRooms[room]
        persisted.preferences.setDeleted(true, room, stamp: stamp())
        do {
            try await close([room])
        } catch {
            persisted.preferences.deletedRooms[room] = answered
            throw error
        }
        Diagnostics.sync.notice("room: deleted a conversation this member was no longer in")
        sendOwnEntries()
    }

    func close(_ rooms: Set<RoomID>) async throws {
        guard !rooms.isEmpty else { return }
        var removed: [Entry] = []
        for room in rooms { removed.append(contentsOf: replica.close(room)) }
        persisted.spentEntries = replica.spentEntries

        do {
            try await saveState()
        } catch {
            for room in rooms { replica.reopen(room) }
            for entry in removed { _ = try? replica.integrate(entry) }
            persisted.spentEntries = replica.spentEntries
            integrity.writesFailed += 1
            Diagnostics.sync.error(
                "storage: could not record a deleted conversation, so nothing was deleted (\(String(describing: error), privacy: .public))")
            throw error
        }

        await finishDeleting(rooms, removing: removed)
        refresh()
    }

    func reopen(_ room: RoomID) {
        guard replica.closedRooms.contains(room) || persisted.preferences.roomsDeleted.contains(room)
        else { return }
        persisted.preferences.setDeleted(false, room, stamp: stamp())
        replica.reopen(room)
        persisted.spentEntries = replica.spentEntries
        Diagnostics.sync.notice("room: let back into a deleted conversation; its history may be asked for again")
    }

    func settleDeletedRooms() async {
        let wanted = persisted.preferences.roomsDeleted
        for room in replica.closedRooms.subtracting(wanted) { reopen(room) }
        let closing = wanted.subtracting(replica.closedRooms)
        guard !closing.isEmpty else { return }
        do {
            try await close(closing)
            Diagnostics.sync.notice(
                "room: deleted \(closing.count, privacy: .public) conversation(s) another of your devices deleted")
        } catch {
            Diagnostics.sync.error(
                "room: could not delete a conversation another of your devices deleted (\(String(describing: error), privacy: .public))")
        }
    }

    func finishDeleting(_ rooms: Set<RoomID>, removing entries: [Entry]) async {
        guard !rooms.isEmpty else { return }

        var named: Set<AttachmentID> = []
        var ownUploads: Set<AttachmentID> = []
        let me = enrolment?.identity.id
        for entry in entries {
            let ids = attachments(namedBy: entry)
            named.formUnion(ids)
            if entry.author == me { ownUploads.formUnion(ids) }
        }
        for id in ownUploads where !persisted.uploadsLeftForOthers.contains(id) {
            persisted.uploadsLeftForOthers.append(id)
        }
        let stillNamed = replica.allEntries.reduce(into: Set<AttachmentID>()) {
            $0.formUnion(attachments(namedBy: $1))
        }
        for id in named.subtracting(stillNamed) {
            do { try await storage.media.remove(id) } catch {
                Diagnostics.sync.error(
                    "media: could not drop a photo from a deleted conversation (\(String(describing: error), privacy: .public))")
            }
        }

        do {
            try await storage.log.removeEntries { entry in entry.room.map(rooms.contains) ?? false }
        } catch {
            integrity.writesFailed += 1
            Diagnostics.sync.error(
                "storage: could not take a deleted conversation out of the log; the next launch tries again (\(String(describing: error), privacy: .public))")
        }

        let removedHashes = Set(entries.map(\.hash))
        for room in rooms {
            var keysGone = true
            for raw in persisted.epochs[room] ?? [] {
                do {
                    try await storage.keychain.remove(Self.epochKey(room, EpochNumber(rawValue: raw)))
                } catch {
                    keysGone = false
                    Diagnostics.sync.error(
                        "keychain: could not remove a deleted conversation's key; the next launch tries again (\(String(describing: error), privacy: .public))")
                }
            }
            chains[room] = nil
            if keysGone {
                persisted.epochs[room] = nil
                persisted.knownRooms.removeAll { $0 == room }
            }

            let invitations = persisted.acceptedInvitations.filter { $0.attestation.room == room }
            for accepted in invitations {
                persisted.phraseNonces[accepted.attestation.joinerCommitment.base64EncodedString()] = nil
            }
            persisted.acceptedInvitations.removeAll { $0.attestation.room == room }
            persisted.greetedRooms.removeAll { $0 == room }
            persisted.readThrough[room] = nil
            persisted.holesNoticed[room] = nil
            persisted.askedAutomatically[room] = nil
            persisted.reviewsPostponed[room] = nil
            persisted.epochTurnsOwed.removeAll { $0 == room }
            persisted.repairs.removeAll { $0.room == room }
            persisted.restoreAsks.removeAll { $0.room == room }
            furthestSeen[room] = nil
            roomsWithUnsentMessages.remove(room)
        }
        persisted.answeredDepartures.subtract(removedHashes)
        for hash in removedHashes { arrivalDelays[hash] = nil }

        await persistOrReport("what is left of a deleted conversation") { try await saveState() }
    }

    func attachments(namedBy entry: Entry) -> Set<AttachmentID> {
        guard let chain = chain(sealing: entry), let payload = entry.opened(using: chain) else { return [] }
        switch payload.type {
        case .media:
            guard let body = try? payload.decode(MediaBody.self) else { return [] }
            return Set(body.all.map(\.attachment.id))
        case .memberPhoto:
            return (try? payload.decode(MemberPhotoBody.self))?.reference.map { [$0.id] } ?? []
        default:
            return []
        }
    }
}
