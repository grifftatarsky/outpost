import AppIntents
import CarpenterKit

struct RoomEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Room")
    static let defaultQuery = RoomQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ entry: FocusFilterStore.RoomEntry) {
        id = entry.id.rawValue.uuidString
        name = entry.name
    }
}

struct RoomQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RoomEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [RoomEntity] {
        all()
    }

    private func all() -> [RoomEntity] {
        FocusFilterStore.shared.rooms().map(RoomEntity.init)
    }
}

struct RoomsFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Rooms that may notify"
    static let description: IntentDescription? = IntentDescription(
        "Which rooms may notify while this Focus is on, and whether banners show what was said.")

    @Parameter(title: "Only these rooms", description: "Leave empty to let every room notify.")
    var rooms: [RoomEntity]?

    @Parameter(title: "Show what was said", default: true)
    var showsPreviews: Bool

    var displayRepresentation: DisplayRepresentation {
        let count = rooms?.count ?? 0
        let title: LocalizedStringResource = count == 0 ? "Every room" : "\(count) rooms"
        let subtitle: LocalizedStringResource = showsPreviews ? "Previews shown" : "Previews hidden"
        return DisplayRepresentation(title: title, subtitle: subtitle)
    }

    func perform() async throws -> some IntentResult {
        let allowed = Set(
            (rooms ?? []).compactMap { UUID(uuidString: $0.id).map(RoomID.init(rawValue:)) })
        FocusFilterStore.shared.write(FocusFilter(rooms: allowed, showsPreviews: showsPreviews))
        return .result()
    }
}
