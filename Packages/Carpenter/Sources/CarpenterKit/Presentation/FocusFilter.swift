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

    public func levelForAPost(own level: NotificationLevel) -> NotificationLevel {
        withoutPreviews(level)
    }

    private func withoutPreviews(_ level: NotificationLevel) -> NotificationLevel {
        guard !showsPreviews, level == .everything else { return level }
        return .whoAndWhere
    }
}

public struct FocusFilterStore: @unchecked Sendable {
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
    private let directory: URL?

    public init(defaults: UserDefaults, directory: URL?) {
        self.defaults = defaults
        self.directory = directory
    }

    public static var shared: FocusFilterStore {
        let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
        return FocusFilterStore(
            defaults: UserDefaults(suiteName: AppGroup.identifier) ?? .standard,
            directory: group?.appending(path: "Focus", directoryHint: .isDirectory))
    }

    private var roomsFile: URL? { directory?.appending(path: "rooms.json") }

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
        guard let roomsFile, let data = try? Data(contentsOf: roomsFile),
            let rooms = try? JSONDecoder().decode([RoomEntry].self, from: data)
        else { return [] }
        return rooms
    }

    public func writeRooms(_ rooms: [RoomEntry]) {
        defaults.removeObject(forKey: Self.roomsKey)
        guard let directory, let roomsFile, let data = try? JSONEncoder().encode(rooms) else { return }
        StorageLocation.leaveOutOfBackups(directory)
        do {
            try data.write(to: roomsFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Diagnostics.sync.error(
                "focus: could not keep the room list (\(String(describing: error), privacy: .public))")
        }
    }
}
