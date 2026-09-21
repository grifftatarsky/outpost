import Foundation

extension Projection {
    // MARK: Conversation

    private func draws(_ entry: RenderedEntry, notIn out: Set<EntryHash>) -> Bool {
        !out.contains(entry.id) || entry.author == viewer
    }

    public func messages(in room: ConversationID, outOfRoom out: Set<EntryHash> = []) -> [Message] {
        rendered
            .filter { $0.room == room && $0.isConversation && draws($0, notIn: out) }
            .map(message)
    }

    public func transcript(
        in room: ConversationID, opening: (RenderedEntry) -> Payload?, outOfRoom out: Set<EntryHash> = []
    ) -> [TranscriptEntry] {
        var items: [TranscriptEntry] = []
        var founder: ParticipantID?
        var named = false
        var offers: [Data: MembershipAttestation] = [:]

        for entry in rendered where entry.room == room {
            guard draws(entry, notIn: out) else { continue }
            if entry.isConversation {
                items.append(.message(message(entry)))
                continue
            }

            let kind: RoomNotice.Kind?
            switch entry.type {
            case .roomProfile:
                guard case .text(let name) = entry.content else { continue }
                if founder == nil { founder = entry.author }
                kind = named
                    ? .renamed(by: member(entry.author), to: name)
                    : entry.roomKind == .solo
                        ? .startedSolo(by: member(entry.author))
                        : .created(by: member(entry.author), named: name)
                named = true

            case .joinRequest:
                guard let body = try? opening(entry)?.decode(JoinRequestBody.self) else { continue }
                offers[body.attestation.signature] = body.attestation
                kind = .invited(
                    member(body.attestation.joiner), by: member(body.attestation.inviter))

            case .joinConfirmed:
                guard let body = try? opening(entry)?.decode(JoinConfirmedBody.self) else { continue }
                kind = .confirmed(member(body.joiner))

            case .soloCheck:
                guard let body = try? opening(entry)?.decode(SoloCheckBody.self) else { continue }
                switch body.move {
                case .asked: kind = .checkAsked(member(entry.author))
                case .confirmed: kind = .checkConfirmed(member(entry.author))
                case .refused: kind = .checkRefused(member(entry.author))
                }

            case .invitationRescinded:
                guard let body = try? opening(entry)?.decode(InvitationRescindedBody.self),
                    let offer = offers[body.invitation]
                else { continue }
                kind = .tookBackInvitation(member(offer.joiner), by: member(entry.author))

            case .admission:
                guard let body = try? opening(entry)?.decode(AdmissionBody.self) else { continue }
                kind = body.admitted
                    ? .admitted(member(body.joiner), by: member(entry.author))
                    : .refused(member(body.joiner), by: member(entry.author))

            case .removal:
                guard let body = try? opening(entry)?.decode(RemovalBody.self) else { continue }
                kind = .removed(member(body.removed), by: member(entry.author))

            case .departure:
                kind = .left(member(entry.author))

            case .roomAccess:
                guard entry.author == founder,
                    let body = try? opening(entry)?.decode(RoomAccessBody.self)
                else { continue }
                kind = .accessChanged(by: member(entry.author), to: body.access)

            default:
                kind = nil
            }

            guard let kind else { continue }
            items.append(.notice(RoomNotice(id: entry.id, kind: kind, at: entry.wallTime)))
        }

        return items
    }

    public func readEvidence(
        in room: ConversationID, opening: (RenderedEntry) -> Payload?
    ) -> ReadEvidence {
        var positionOfEntry: [EntryHash: Int] = [:]
        for (position, entry) in rendered.enumerated() where entry.room == room {
            positionOfEntry[entry.id] = position
        }

        var steps: [ReadEvidence.Mark] = []
        for entry in rendered
        where entry.room == room && entry.type == .readReceipt && entry.author != viewer {
            guard let payload = opening(entry),
                let body = try? JSONDecoder().decode(ReadReceiptBody.self, from: payload.body),
                let position = positionOfEntry[body.target]
            else { continue }
            steps.append(ReadEvidence.Mark(position: position, at: entry.wallTime))
        }
        return ReadEvidence(steps)
    }

    public func readEvidence(
        in room: ConversationID, byEachMember opening: (RenderedEntry) -> Payload?
    ) -> [ParticipantID: ReadEvidence] {
        var positionOfEntry: [EntryHash: Int] = [:]
        for (position, entry) in rendered.enumerated() where entry.room == room {
            positionOfEntry[entry.id] = position
        }

        var steps: [ParticipantID: [ReadEvidence.Mark]] = [:]
        for entry in rendered
        where entry.room == room && entry.type == .readReceipt && entry.author != viewer {
            guard let payload = opening(entry),
                let body = try? JSONDecoder().decode(ReadReceiptBody.self, from: payload.body),
                let position = positionOfEntry[body.target]
            else { continue }
            steps[entry.author, default: []]
                .append(ReadEvidence.Mark(position: position, at: entry.wallTime))
        }
        return steps.mapValues { ReadEvidence($0) }
    }

    public func reportingMembers(
        in room: ConversationID, opening: (RenderedEntry) -> Payload?
    ) -> Set<ParticipantID> {
        var reports: [ParticipantID: Bool] = [:]
        for entry in rendered where entry.room == room && entry.type == .readPolicy {
            guard let payload = opening(entry),
                let body = try? JSONDecoder().decode(ReadPolicyBody.self, from: payload.body)
            else { continue }
            reports[entry.author] = body.reports
        }
        return Set(reports.filter(\.value).keys)
    }

    public func positions(in room: ConversationID) -> [MessageID: Int] {
        var found: [MessageID: Int] = [:]
        for (position, entry) in rendered.enumerated()
        where entry.room == room && entry.isConversation {
            found[MessageID(entry: entry.id)] = position
        }
        return found
    }

    private func message(_ entry: RenderedEntry) -> Message {
        let media: MediaAttachment?
        let body: String
        if case .media(let photo) = entry.content {
            media = MediaAttachment(photo)
            body = photo.caption ?? ""
        } else {
            media = nil
            body = preview(entry)
        }
        return Message(
            id: MessageID(entry: entry.id),
            author: member(entry.author),
            body: body,
            sentAt: entry.wallTime,
            isMine: entry.author == viewer,
            editedAt: entry.editedAt,
            reactions: entry.reactions,
            myReaction: entry.reactions.first { $0.value.contains(viewer) }?.key,
            isWithdrawn: {
                if case .withdrawn = entry.content { return true }
                return false
            }(),
            revisions: entry.revisions,
            media: media
        )
    }
}
