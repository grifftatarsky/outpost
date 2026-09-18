import Foundation

public struct Connection: Identifiable, Hashable, Sendable {
    public let person: Member
    public let sharedRooms: Int
    public let seesTheirOutpost: Bool

    public var id: ParticipantID { person.id }

    public init(person: Member, sharedRooms: Int, seesTheirOutpost: Bool) {
        self.person = person
        self.sharedRooms = sharedRooms
        self.seesTheirOutpost = seesTheirOutpost
    }

    public var isOnlyByOutpost: Bool { sharedRooms == 0 && seesTheirOutpost }
}

extension Connection {
    public static func all(
        rosters: [Set<ParticipantID>],
        outpostAuthors: [Member],
        viewer: ParticipantID,
        excluding excluded: Set<ParticipantID> = [],
        naming: (ParticipantID) -> Member
    ) -> [Connection] {
        var sharedRooms: [ParticipantID: Int] = [:]
        for roster in rosters {
            for person in roster { sharedRooms[person, default: 0] += 1 }
        }

        let readable = Set(outpostAuthors.map(\.id))
        let omitted = excluded.union([viewer])

        return Set(sharedRooms.keys).union(readable)
            .subtracting(omitted)
            .map { person in
                Connection(
                    person: naming(person),
                    sharedRooms: sharedRooms[person] ?? 0,
                    seesTheirOutpost: readable.contains(person))
            }
            .sorted(by: Connection.byName)
    }

    static func byName(_ lhs: Connection, _ rhs: Connection) -> Bool {
        let order = lhs.person.displayName.localizedStandardCompare(rhs.person.displayName)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.person.id.rawValue.lexicographicallyPrecedes(rhs.person.id.rawValue)
    }
}

extension Collection where Element == Connection {
    public func matching(_ query: String) -> [Connection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(self) }
        return filter {
            $0.person.displayName.localizedStandardContains(trimmed)
                || $0.person.id.shortCode.localizedStandardContains(trimmed)
        }
    }

    public func sectionedByInitial() -> [(title: String, people: [Connection])] {
        let grouped = Dictionary(grouping: self) { connection -> String in
            let initial = connection.person.displayName
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .first
            guard let initial, initial.isLetter else { return "#" }
            return String(initial).uppercased()
        }
        return grouped.keys
            .sorted { lhs, rhs in
                if lhs == "#" { return false }
                if rhs == "#" { return true }
                return lhs < rhs
            }
            .map { ($0, grouped[$0, default: []].sorted(by: Connection.byName)) }
    }
}
