import Foundation

public struct TagID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct OrganisationStamp: Hashable, Sendable, Codable, Comparable {
    public let at: Date
    public let device: DeviceID

    public init(at: Date, device: DeviceID) {
        self.at = at
        self.device = device
    }

    public static func < (lhs: OrganisationStamp, rhs: OrganisationStamp) -> Bool {
        if lhs.at != rhs.at { return lhs.at < rhs.at }
        return lhs.device.rawValue.lexicographicallyPrecedes(rhs.device.rawValue)
    }
}

public struct Stamped<Value: Hashable & Sendable & Codable>: Hashable, Sendable, Codable {
    public var value: Value
    public var stamp: OrganisationStamp

    public init(_ value: Value, stamp: OrganisationStamp) {
        self.value = value
        self.stamp = stamp
    }

    public func merged(with other: Stamped) -> Stamped {
        other.stamp > stamp ? other : self
    }
}

extension Stamped where Value == Date {
    public func earlier(than other: Stamped) -> Stamped {
        if value != other.value { return value < other.value ? self : other }
        return other.stamp < stamp ? other : self
    }
}

public enum ManagedTagKind: String, Hashable, Sendable, Codable, CaseIterable {
    case invited

    public var id: TagID {
        switch self {
        case .invited: return TagID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-00074A9DED01")!)
        }
    }
}

public struct ManagedTag: Identifiable, Hashable, Sendable {
    public let kind: ManagedTagKind
    public let rooms: Set<RoomID>

    public var id: TagID { kind.id }

    public var isWorthShowing: Bool { !rooms.isEmpty }

    public init(kind: ManagedTagKind, rooms: Set<RoomID>) {
        self.kind = kind
        self.rooms = rooms
    }
}

public struct RoomTag: Identifiable, Hashable, Sendable, Codable {
    public let id: TagID
    public var name: Stamped<String>
    public var order: Stamped<Double>

    public init(id: TagID = TagID(), name: Stamped<String>, order: Stamped<Double>) {
        self.id = id
        self.name = name
        self.order = order
    }

    public func merged(with other: RoomTag) -> RoomTag {
        RoomTag(id: id, name: name.merged(with: other.name), order: order.merged(with: other.order))
    }
}

public struct RoomOrganisation: Hashable, Sendable, Codable {
    public var pin: Stamped<Double?>
    public var tags: [TagID: Stamped<Bool>]

    public init(
        pin: Stamped<Double?>,
        tags: [TagID: Stamped<Bool>] = [:]
    ) {
        self.pin = pin
        self.tags = tags
    }

    public var isPinned: Bool { pin.value != nil }

    public var assignedTags: Set<TagID> {
        Set(tags.filter(\.value.value).keys)
    }

    public func merged(with other: RoomOrganisation) -> RoomOrganisation {
        var merged = RoomOrganisation(
            pin: pin.merged(with: other.pin),
            tags: tags
        )
        for (tag, assignment) in other.tags {
            merged.tags[tag] = merged.tags[tag].map { $0.merged(with: assignment) } ?? assignment
        }
        return merged
    }
}

public struct RoomsListOrganisation: Hashable, Sendable, Codable {
    public var tags: [TagID: RoomTag]
    public var rooms: [RoomID: RoomOrganisation]

    public init(tags: [TagID: RoomTag] = [:], rooms: [RoomID: RoomOrganisation] = [:]) {
        self.tags = tags
        self.rooms = rooms
    }

    public var orderedTags: [RoomTag] {
        tags.values.sorted {
            if $0.order.value != $1.order.value { return $0.order.value < $1.order.value }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }

    public func organisation(of room: RoomID) -> RoomOrganisation? { rooms[room] }

    public func isPinned(_ room: RoomID) -> Bool { rooms[room]?.isPinned ?? false }

    public func tags(of room: RoomID) -> Set<TagID> { rooms[room]?.assignedTags ?? [] }

    public func roomCount(taggedWith tag: TagID) -> Int {
        rooms.values.count { $0.assignedTags.contains(tag) }
    }

    public func arrange(
        _ summaries: [RoomSummary], filteredBy tag: TagID? = nil, managed: [ManagedTag] = []
    ) -> [RoomSummary] {
        let visible = tag.map { tag in
            if let managed = managed.first(where: { $0.id == tag }) {
                return summaries.filter { managed.rooms.contains($0.id) }
            }
            return summaries.filter { rooms[$0.id]?.assignedTags.contains(tag) ?? false }
        } ?? summaries

        let pinned = visible.filter { isPinned($0.id) }
            .sorted {
                let left = rooms[$0.id]?.pin.value ?? 0
                let right = rooms[$1.id]?.pin.value ?? 0
                if left != right { return left < right }
                return $0.lastActivity > $1.lastActivity
            }

        let rest = visible.filter { !isPinned($0.id) }
            .sorted {
                if $0.lastActivity != $1.lastActivity { return $0.lastActivity > $1.lastActivity }
                return $0.name < $1.name
            }

        return pinned + rest
    }

    // MARK: Editing

    public mutating func setPinned(
        _ pinned: Bool, for room: RoomID, stamp: OrganisationStamp
    ) {
        let position = pinned ? (lowestPinOrder() - 1) : nil
        update(room, stamp: stamp) { $0.pin = Stamped(position, stamp: stamp) }
    }

    public mutating func movePin(
        _ room: RoomID, between above: RoomID?, and below: RoomID?, stamp: OrganisationStamp
    ) {
        let upper = above.flatMap { rooms[$0]?.pin.value } ?? (lowestPinOrder() - 2)
        let lower = below.flatMap { rooms[$0]?.pin.value } ?? (highestPinOrder() + 2)
        update(room, stamp: stamp) { $0.pin = Stamped((upper + lower) / 2, stamp: stamp) }
    }

    public mutating func setTag(
        _ tag: TagID, on assigned: Bool, for room: RoomID, stamp: OrganisationStamp
    ) {
        update(room, stamp: stamp) { $0.tags[tag] = Stamped(assigned, stamp: stamp) }
    }

    @discardableResult
    public mutating func addTag(named name: String, stamp: OrganisationStamp) -> TagID {
        let tag = RoomTag(
            name: Stamped(name, stamp: stamp),
            order: Stamped(highestTagOrder() + 1, stamp: stamp)
        )
        tags[tag.id] = tag
        return tag.id
    }

    public mutating func rename(_ tag: TagID, to name: String, stamp: OrganisationStamp) {
        tags[tag]?.name = Stamped(name, stamp: stamp)
    }

    public mutating func moveTag(
        _ tag: TagID, between above: TagID?, and below: TagID?, stamp: OrganisationStamp
    ) {
        let upper = above.flatMap { tags[$0]?.order.value } ?? (lowestTagOrder() - 2)
        let lower = below.flatMap { tags[$0]?.order.value } ?? (highestTagOrder() + 2)
        tags[tag]?.order = Stamped((upper + lower) / 2, stamp: stamp)
    }

    public mutating func removeTag(_ tag: TagID, stamp: OrganisationStamp) {
        tags[tag] = nil
        for room in rooms.keys {
            rooms[room]?.tags[tag] = Stamped(false, stamp: stamp)
        }
    }

    public mutating func forget(_ room: RoomID) {
        rooms[room] = nil
    }

    public func merged(with other: RoomsListOrganisation) -> RoomsListOrganisation {
        var merged = self
        for (id, tag) in other.tags {
            merged.tags[id] = merged.tags[id].map { $0.merged(with: tag) } ?? tag
        }
        for (id, organisation) in other.rooms {
            merged.rooms[id] =
                merged.rooms[id].map { $0.merged(with: organisation) } ?? organisation
        }
        return merged
    }

    private mutating func update(
        _ room: RoomID, stamp: OrganisationStamp, _ change: (inout RoomOrganisation) -> Void
    ) {
        var organisation =
            rooms[room]
            ?? RoomOrganisation(pin: Stamped(nil, stamp: stamp))
        change(&organisation)
        rooms[room] = organisation
    }

    private func lowestPinOrder() -> Double {
        rooms.values.compactMap(\.pin.value).min() ?? 0
    }

    private func highestPinOrder() -> Double {
        rooms.values.compactMap(\.pin.value).max() ?? 0
    }

    private func highestTagOrder() -> Double {
        tags.values.map(\.order.value).max() ?? 0
    }

    private func lowestTagOrder() -> Double {
        tags.values.map(\.order.value).min() ?? 0
    }
}
