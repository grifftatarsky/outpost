import CarpenterKit
import SwiftUI

public enum TagFilterStyle: String, CaseIterable, Sendable, Codable {
    case chips

    case menu
}

public enum RoomsListDensity: String, CaseIterable, Sendable, Codable {
    case comfortable
    case compact
}

public enum InboxArrangement: String, CaseIterable, Sendable, Codable {
    case split
    case merged
}

@MainActor
@Observable
public final class RoomsListPreferences {
    private static let filterStyleKey = "roomsList.tagFilterStyle"
    private static let densityKey = "roomsList.density"
    private static let inboxKey = "roomsList.inbox"
    private static let avatarsKey = "roomsList.showsAvatars"
    private static let bringsPeopleKey = "newRoom.bringsPeople"

    private let defaults: UserDefaults

    public var tagFilterStyle: TagFilterStyle {
        didSet { defaults.set(tagFilterStyle.rawValue, forKey: Self.filterStyleKey) }
    }

    public var density: RoomsListDensity {
        didSet { defaults.set(density.rawValue, forKey: Self.densityKey) }
    }

    public var inbox: InboxArrangement {
        didSet { defaults.set(inbox.rawValue, forKey: Self.inboxKey) }
    }

    public var bringsPeopleIn: Bool {
        didSet { defaults.set(bringsPeopleIn, forKey: Self.bringsPeopleKey) }
    }

    public var showsAvatars: Bool {
        didSet { defaults.set(showsAvatars, forKey: Self.avatarsKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tagFilterStyle =
            defaults.string(forKey: Self.filterStyleKey)
            .flatMap(TagFilterStyle.init(rawValue:)) ?? .chips
        density =
            defaults.string(forKey: Self.densityKey)
            .flatMap(RoomsListDensity.init(rawValue:)) ?? .comfortable
        bringsPeopleIn = defaults.bool(forKey: Self.bringsPeopleKey)
        inbox =
            defaults.string(forKey: Self.inboxKey)
            .flatMap(InboxArrangement.init(rawValue:)) ?? .split
        showsAvatars = defaults.object(forKey: Self.avatarsKey) as? Bool ?? true
    }
}
