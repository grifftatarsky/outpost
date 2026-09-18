import Foundation

public struct ReadEvidence: Hashable, Sendable {
    public struct Mark: Hashable, Sendable {
        public let position: Int
        public let at: Date

        public init(position: Int, at: Date) {
            self.position = position
            self.at = at
        }
    }

    private let marks: [Mark]

    public let furthest: Int?

    public init(_ steps: [Mark]) {
        let ascending = steps.sorted { $0.position < $1.position }
        var descending: [Mark] = []
        descending.reserveCapacity(ascending.count)
        var earliest: Date?
        for mark in ascending.reversed() {
            let at = earliest.map { Swift.min($0, mark.at) } ?? mark.at
            earliest = at
            descending.append(Mark(position: mark.position, at: at))
        }
        marks = descending.reversed()
        furthest = ascending.last?.position
    }

    public var isEmpty: Bool { marks.isEmpty }

    public func firstCovering(_ position: Int) -> Date? {
        var low = 0
        var high = marks.count
        while low < high {
            let middle = low + (high - low) / 2
            if marks[middle].position >= position {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low < marks.count ? marks[low].at : nil
    }
}

public enum ReadReport: Hashable, Sendable {
    case displayed(at: Date)
    case nothingYet
    case doesNotReport

    public var wasDisplayed: Bool {
        if case .displayed = self { return true }
        return false
    }
}

public struct ReadBy: Hashable, Sendable, Identifiable {
    public let member: Member
    public let report: ReadReport

    public var id: ParticipantID { member.id }

    public init(member: Member, report: ReadReport) {
        self.member = member
        self.report = report
    }
}
