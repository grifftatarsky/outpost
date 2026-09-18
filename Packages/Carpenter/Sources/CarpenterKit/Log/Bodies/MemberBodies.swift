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
