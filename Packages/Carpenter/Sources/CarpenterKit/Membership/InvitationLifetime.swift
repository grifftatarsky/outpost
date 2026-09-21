import Foundation

public enum InvitationLifetime: Hashable, Sendable, CaseIterable {
    case aDay
    case aWeek
    case thirtyDays
    case until(Date)
    case indefinite

    public static var allCases: [InvitationLifetime] { [.aDay, .aWeek, .thirtyDays, .indefinite] }

    public var isPickedDate: Bool {
        if case .until = self { return true }
        return false
    }

    public static func endOfDay(
        _ day: Date, in calendar: Calendar = .autoupdatingCurrent
    ) -> InvitationLifetime {
        let end =
            calendar.date(bySettingHour: 23, minute: 59, second: 59, of: day)
            ?? calendar.startOfDay(for: day)
        return .until(end)
    }

    public func expiry(from issuedAt: Date) -> Date {
        switch self {
        case .aDay: return issuedAt.addingTimeInterval(24 * 60 * 60)
        case .aWeek: return issuedAt.addingTimeInterval(7 * 24 * 60 * 60)
        case .thirtyDays: return issuedAt.addingTimeInterval(30 * 24 * 60 * 60)
        case .until(let date): return date
        case .indefinite: return .distantFuture
        }
    }

    public var isIndefinite: Bool {
        switch self {
        case .indefinite: return true
        case .until(let date): return date >= .distantFuture
        case .aDay, .aWeek, .thirtyDays: return false
        }
    }
}

extension MembershipAttestation {
    public static func issue(
        joining room: ConversationID,
        joinerKeys: IdentityPublicKeys,
        by identity: Identity,
        at issuedAt: Date,
        lasting lifetime: InvitationLifetime,
        joinerCommitment: Data = Data(),
        joinerRequires: PhraseLength = .standard,
        inviterRequires: PhraseLength = .standard,
        sharesHistory: Bool = true
    ) throws -> MembershipAttestation {
        var attestation = MembershipAttestation(
            room: room,
            joiner: joinerKeys.participantID,
            joinerKeys: joinerKeys,
            inviter: identity.id,
            inviterKeys: identity.publicKeys,
            issuedAt: issuedAt,
            expiresAt: lifetime.expiry(from: issuedAt),
            joinerCommitment: joinerCommitment,
            joinerRequires: joinerRequires,
            inviterRequires: inviterRequires,
            sharesHistory: sharesHistory,
            signature: Data()
        )
        attestation.signature = try identity.sign(attestation.signingPayload)
        return attestation
    }

    public static func issue(
        joining room: ConversationID,
        code: JoinerCode,
        by identity: Identity,
        at issuedAt: Date,
        lasting lifetime: InvitationLifetime,
        requiring mine: PhraseLength = .standard,
        sharesHistory: Bool = true
    ) throws -> MembershipAttestation {
        try issue(
            joining: room, joinerKeys: code.keys, by: identity, at: issuedAt, lasting: lifetime,
            joinerCommitment: code.commitment, joinerRequires: code.requires,
            inviterRequires: mine, sharesHistory: sharesHistory)
    }

    public func hasLapsed(at instant: Date) -> Bool { instant >= expiresAt }
}
