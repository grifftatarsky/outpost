import Foundation

public struct FocusFilter: Hashable, Sendable, Codable {
    public var rooms: Set<RoomID>
    public var showsPreviews: Bool

    public init(rooms: Set<RoomID> = [], showsPreviews: Bool = true) {
        self.rooms = rooms
        self.showsPreviews = showsPreviews
    }

    public var isNeutral: Bool { rooms.isEmpty && showsPreviews }

    public func allows(_ room: RoomID) -> Bool { rooms.isEmpty || rooms.contains(room) }

    public func level(for room: RoomID, own level: NotificationLevel) -> NotificationLevel {
        guard allows(room) else { return .nothing }
        return withoutPreviews(level)
    }

    /// A post belongs to no room, so the room list cannot speak to it and does not try. The
    /// preview switch can: the Focus filter offers *Show what was said* over banners, not over
    /// banners about rooms, and a post's words are what was said.
    public func levelForAPost(own level: NotificationLevel) -> NotificationLevel {
        withoutPreviews(level)
    }

    private func withoutPreviews(_ level: NotificationLevel) -> NotificationLevel {
        guard !showsPreviews, level == .everything else { return level }
        return .whoAndWhere
    }
}

public struct FocusFilterStore: @unchecked Sendable {  // UserDefaults is thread-safe by contract
    public struct RoomEntry: Hashable, Sendable, Codable {
        public let id: RoomID
        public let name: String

        public init(id: RoomID, name: String) {
            self.id = id
            self.name = name
        }
    }

    private static let filterKey = "focusFilter.current"
    private static let roomsKey = "focusFilter.rooms"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public static var shared: FocusFilterStore {
        FocusFilterStore(defaults: UserDefaults(suiteName: AppGroup.identifier) ?? .standard)
    }

    public func read() -> FocusFilter {
        guard let data = defaults.data(forKey: Self.filterKey),
            let filter = try? JSONDecoder().decode(FocusFilter.self, from: data)
        else { return FocusFilter() }
        return filter
    }

    public func write(_ filter: FocusFilter) {
        if filter.isNeutral {
            defaults.removeObject(forKey: Self.filterKey)
        } else if let data = try? JSONEncoder().encode(filter) {
            defaults.set(data, forKey: Self.filterKey)
        }
    }

    public func rooms() -> [RoomEntry] {
        guard let data = defaults.data(forKey: Self.roomsKey),
            let rooms = try? JSONDecoder().decode([RoomEntry].self, from: data)
        else { return [] }
        return rooms
    }

    public func writeRooms(_ rooms: [RoomEntry]) {
        guard let data = try? JSONEncoder().encode(rooms) else { return }
        defaults.set(data, forKey: Self.roomsKey)
    }
}
