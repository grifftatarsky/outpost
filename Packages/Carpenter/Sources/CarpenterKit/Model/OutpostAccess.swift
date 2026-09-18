import Foundation

public struct AccessWindow: Hashable, Sendable, Codable {
    public var from: Date?
    public var until: Date?

    public init(from: Date? = nil, until: Date? = nil) {
        self.from = from
        self.until = until
    }

    public func contains(_ moment: Date) -> Bool {
        if let from, moment < from { return false }
        if let until, moment >= until { return false }
        return true
    }

    public var isOpen: Bool { until == nil }

    public var isEverything: Bool { from == nil && until == nil }
}

public struct OutpostAccess: Hashable, Sendable, Codable {
    public private(set) var granted: [ParticipantID: Stamped<Grant>]

    public init(granted: [ParticipantID: Stamped<Grant>] = [:]) {
        self.granted = granted
    }

    public struct Grant: Hashable, Sendable, Codable {
        public var windows: [AccessWindow]
        public var origin: Origin
        public var chosenIn: RoomID?

        public init(
            windows: [AccessWindow], origin: Origin = .chosen, chosenIn: RoomID? = nil
        ) {
            self.windows = windows
            self.origin = origin
            self.chosenIn = chosenIn
        }

        public init(
            from: Date? = nil, isAllowed: Bool = true, origin: Origin = .chosen,
            chosenIn: RoomID? = nil
        ) {
            self.init(
                windows: isAllowed ? [AccessWindow(from: from)] : [],
                origin: origin, chosenIn: chosenIn)
        }

        public var isAllowed: Bool { windows.contains(where: \.isOpen) }

        public var from: Date? { windows.last(where: \.isOpen)?.from }

        mutating func open(at moment: Date?) {
            guard !isAllowed else { return }
            windows.append(AccessWindow(from: moment))
        }

        mutating func openEverything() {
            windows = [AccessWindow()]
        }

        mutating func close(at moment: Date) {
            guard let last = windows.indices.last, windows[last].isOpen else { return }
            windows[last].until = moment
        }
    }

    public enum Origin: String, Hashable, Sendable, Codable {
        case chosen
        case inherited
    }

    public enum Choice: Hashable, Sendable {
        case fromNow
        case everything
        case no
    }

    public enum Standing: Hashable, Sendable {
        case none
        case from(Date)
        case everything

        public init(_ grant: Grant?) {
            guard let open = grant?.windows.last(where: \.isOpen) else {
                self = .none
                return
            }
            self = open.from.map(Standing.from) ?? .everything
        }

        public var offers: [Choice] {
            switch self {
            case .none: return [.fromNow, .everything]
            case .from: return [.no, .everything]
            case .everything: return [.no]
            }
        }

        public static func isFinal(_ choice: Choice) -> Bool { choice == .everything }
    }

    // MARK: Asking

    public func allows(_ person: ParticipantID, at postedAt: Date) -> Bool {
        guard let grant = granted[person]?.value else { return false }
        return grant.windows.contains { $0.contains(postedAt) }
    }

    public func audience(at moment: Date = .now) -> Set<ParticipantID> {
        Set(granted.keys.filter { allows($0, at: moment) })
    }

    public func grant(for person: ParticipantID) -> Grant? {
        granted[person]?.value
    }

    public func standing(for person: ParticipantID) -> Standing {
        Standing(grant(for: person))
    }

    // MARK: Changing

    public mutating func allow(
        _ person: ParticipantID, from: Date? = nil, origin: Origin = .chosen,
        chosenIn: RoomID? = nil, stamp: OrganisationStamp
    ) {
        var grant = granted[person]?.value ?? Grant(windows: [])
        if let from { grant.open(at: from) } else { grant.openEverything() }
        grant.origin = origin
        grant.chosenIn = chosenIn ?? grant.chosenIn
        granted[person] = Stamped(grant, stamp: stamp)
    }

    public mutating func revoke(
        _ person: ParticipantID, chosenIn: RoomID? = nil, stamp: OrganisationStamp
    ) {
        var grant = granted[person]?.value ?? Grant(windows: [])
        grant.close(at: stamp.at)
        grant.chosenIn = chosenIn ?? grant.chosenIn
        granted[person] = Stamped(grant, stamp: stamp)
    }

    public func merged(with other: OutpostAccess) -> OutpostAccess {
        var result = granted
        for (person, theirs) in other.granted {
            result[person] = result[person].map { $0.merged(with: theirs) } ?? theirs
        }
        return OutpostAccess(granted: result)
    }
}
