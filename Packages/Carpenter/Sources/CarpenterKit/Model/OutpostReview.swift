import Foundation

public struct OutpostReview: Hashable, Sendable, Identifiable {
    public let room: ConversationID
    public let roomName: String
    public let people: [Person]

    public var id: ConversationID { room }

    public init(room: ConversationID, roomName: String, people: [Person]) {
        self.room = room
        self.roomName = roomName
        self.people = people.sorted { left, right in
            if left.isUndecided != right.isUndecided { return left.isUndecided }
            return left.member.displayName < right.member.displayName
        }
    }

    public struct Person: Hashable, Sendable, Identifiable {
        public let member: Member
        public let grant: OutpostAccess.Grant?
        public let decidedIn: String?

        public var id: ParticipantID { member.id }

        public var isUndecided: Bool { grant == nil }

        public var isAllowed: Bool { grant?.isAllowed == true }

        public init(member: Member, grant: OutpostAccess.Grant?, decidedIn: String? = nil) {
            self.member = member
            self.grant = grant
            self.decidedIn = decidedIn
        }
    }

    public var undecided: [Person] { people.filter(\.isUndecided) }

    public var alreadyAllowed: [Person] { people.filter(\.isAllowed) }

    public var isWorthAsking: Bool { !undecided.isEmpty }
}
