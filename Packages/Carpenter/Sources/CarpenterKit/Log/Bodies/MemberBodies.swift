import Foundation

// MARK: What a member publishes about themselves

public struct FocusStatusBody: Hashable, Sendable, Codable {
    public static let messageLimit = 60

    public let silenced: Bool
    public let message: String?

    public init(silenced: Bool, message: String? = nil) {
        self.silenced = silenced
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.message = silenced && !trimmed.isEmpty ? String(trimmed.prefix(Self.messageLimit)) : nil
    }
}

public struct SupporterBadgeBody: Hashable, Sendable, Codable {
    public let shows: Bool

    public init(shows: Bool) {
        self.shows = shows
    }
}

public struct MemberPhotoBody: Hashable, Sendable, Codable {
    public let reference: AttachmentReference?

    public init(reference: AttachmentReference?) {
        self.reference = reference
    }
}

public struct MemberProfileBody: Hashable, Sendable, Codable {
    public let displayName: String?

    public let blurb: String?

    public static let blurbLimit = 160

    public init(displayName: String?, blurb: String? = nil) {
        self.displayName = (displayName?.isEmpty ?? true) ? nil : displayName
        self.blurb = blurb.map { String($0.prefix(Self.blurbLimit)) }
    }

    public var name: String? { (displayName?.isEmpty ?? true) ? nil : displayName }

    private enum CodingKeys: String, CodingKey { case displayName, blurb }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        blurb = try container.decodeIfPresent(String.self, forKey: .blurb)
            .map { String($0.prefix(Self.blurbLimit)) }
    }
}

public struct PairLinkBody: Hashable, Sendable, Codable {
    public let recipient: ParticipantID
    public let sealed: Data

    public init(recipient: ParticipantID, sealed: Data) {
        self.recipient = recipient
        self.sealed = sealed
    }

    public static func seal(
        _ link: PairLink, from sender: ParticipantID, to recipient: ParticipantID, with secret: PairwiseSecret
    ) throws -> PairLinkBody {
        PairLinkBody(
            recipient: recipient,
            sealed: try secret.wrap(
                try JSONEncoder().encode(link), context: PairwiseSecret.linkContext(from: sender, to: recipient)))
    }

    public func open(from sender: ParticipantID, with secret: PairwiseSecret) -> PairLink? {
        guard let plaintext = try? secret.unwrap(sealed, context: PairwiseSecret.linkContext(from: sender, to: recipient))
        else { return nil }
        return try? JSONDecoder().decode(PairLink.self, from: plaintext)
    }
}
