import Foundation

// MARK: Every payload this app can write

extension Payload {
    public static func post(_ text: String) throws -> Payload {
        Payload(type: .post, body: try encode(PostBody(text: text)), fallbackText: text)
    }

    public static func edit(_ target: EntryHash, to text: String) throws -> Payload {
        Payload(type: .edit, body: try encode(EditBody(target: target, text: text)))
    }

    public static func tombstone(_ target: EntryHash) throws -> Payload {
        Payload(type: .tombstone, body: try encode(TombstoneBody(target: target)))
    }

    public static func reaction(_ target: EntryHash, emoji: String?) throws -> Payload {
        Payload(type: .reaction, body: try encode(ReactionBody(target: target, emoji: emoji)))
    }

    public static func comment(on target: EntryHash, text: String) throws -> Payload {
        Payload(
            type: .comment, body: try encode(CommentBody(target: target, text: text)),
            fallbackText: text)
    }

    public static func joinRequest(_ attestation: MembershipAttestation) throws -> Payload {
        Payload(
            type: .joinRequest, body: try encode(JoinRequestBody(attestation: attestation)),
            fallbackText: nil)
    }

    public static func joinConfirmed(_ body: JoinConfirmedBody) throws -> Payload {
        Payload(
            type: .joinConfirmed, body: try encode(body),
            fallbackText: String(
                localized: "Somebody confirmed their invitation.", bundle: .module))
    }

    public static func invitationRescinded(of attestation: MembershipAttestation) throws -> Payload {
        Payload(
            type: .invitationRescinded,
            body: try encode(InvitationRescindedBody(invitation: attestation.signature)),
            fallbackText: String(
                localized: "An invitation was taken back.", bundle: .module))
    }

    public static func soloCheck(_ body: SoloCheckBody) throws -> Payload {
        let fallback: String
        switch body.move {
        case .asked:
            fallback = String(
                localized: "Somebody asked to check who they are talking to.", bundle: .module)
        case .confirmed:
            fallback = String(localized: "Somebody confirmed the check.", bundle: .module)
        case .refused:
            fallback = String(
                localized: "Somebody said the check did not match.", bundle: .module)
        }
        return Payload(type: .soloCheck, body: try encode(body), fallbackText: fallback)
    }

    public static func removal(of member: ParticipantID) throws -> Payload {
        Payload(
            type: .removal, body: try encode(RemovalBody(removed: member)), fallbackText: nil)
    }

    public static func departure() throws -> Payload {
        Payload(type: .departure, body: try encode(DepartureBody()), fallbackText: nil)
    }

    public static func admission(
        of joiner: ParticipantID, admitted: Bool, invitation: Data? = nil,
        sinceEpoch: UInt64? = nil
    ) throws -> Payload {
        Payload(
            type: .admission,
            body: try encode(
                AdmissionBody(
                    joiner: joiner, admitted: admitted, invitation: invitation,
                    sinceEpoch: sinceEpoch)),
            fallbackText: nil)
    }

    public static func roomState(_ body: RoomStateBody) throws -> Payload {
        Payload(type: .roomState, body: try encode(body), fallbackText: nil)
    }

    public static func epochChange(_ link: EpochLink) throws -> Payload {
        Payload(
            type: .epochChange, body: try encode(EpochChangeBody(link: link)),
            fallbackText: nil)
    }

    public static func roomAccess(_ access: RoomAccess) throws -> Payload {
        Payload(
            type: .roomAccess, body: try encode(RoomAccessBody(access: access)),
            fallbackText: nil)
    }

    public static func readReceipt(upTo target: EntryHash) throws -> Payload {
        Payload(type: .readReceipt, body: try encode(ReadReceiptBody(target: target)))
    }

    public static func readPolicy(reports: Bool) throws -> Payload {
        Payload(type: .readPolicy, body: try encode(ReadPolicyBody(reports: reports)))
    }

    public static func roomProfile(name: String, kind: RoomKind = .room) throws -> Payload {
        Payload(
            type: .roomProfile, body: try encode(RoomProfileBody(name: name, kind: kind)),
            fallbackText: name)
    }

    public static func focusStatus(_ status: FocusStatusBody) throws -> Payload {
        Payload(type: .focusStatus, body: try encode(status))
    }

    public static func supporterBadge(shows: Bool) throws -> Payload {
        Payload(type: .supporterBadge, body: try encode(SupporterBadgeBody(shows: shows)))
    }

    public static func outpostAccess(_ change: OutpostAccessBody) throws -> Payload {
        Payload(type: .outpostAccess, body: try encode(change))
    }

    public static func memberPhoto(_ reference: AttachmentReference?) throws -> Payload {
        Payload(type: .memberPhoto, body: try encode(MemberPhotoBody(reference: reference)))
    }

    public static func commentTally(post: EntryHash, total: Int) throws -> Payload {
        Payload(
            type: .commentTally,
            body: try encode(CommentTallyBody(post: post, total: total)),
            fallbackText: "")
    }

    public static func memberProfile(displayName: String?, blurb: String? = nil) throws -> Payload {
        let body = MemberProfileBody(displayName: displayName, blurb: blurb)
        return Payload(
            type: .memberProfile, body: try encode(body), fallbackText: body.name ?? "")
    }

    public static func media(_ body: MediaBody) throws -> Payload {
        if let preview = body.preview, preview.count > MediaBody.previewByteCap {
            throw AttachmentError.previewTooLarge
        }
        return Payload(type: .media, body: try encode(body), fallbackText: body.line)
    }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: body)
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }
}
