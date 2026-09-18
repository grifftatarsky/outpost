import CarpenterKit
import Foundation
import Testing

@testable import CarpenterUI

@Suite("A room stays a room when somebody joins")
struct RoomsStayVisibleTests {
    private func room(named name: String, members: Int, isDirect: Bool = false) -> RoomSummary {
        RoomSummary(
            name: name, memberCount: members, lastAuthor: nil, lastMessage: "",
            lastActivity: Date(timeIntervalSince1970: 0), hasUnread: false, isDirect: isDirect)
    }

    @Test("A two-person room is still a room")
    func twoPersonRoomIsStillAGroup() {
        let made = room(named: "Proof Room", members: 2)

        #expect(made.isDirect == false)
        #expect(InboxScope.groups.includes(made), "the Rooms tab dropped a room somebody made")
        #expect(!InboxScope.direct.includes(made))
    }

    @Test("Headcount never decides whether a conversation is direct")
    func headcountDoesNotDecide() {
        for members in [1, 2, 3, 8] {
            #expect(room(named: "Room", members: members).isDirect == false, "\(members) members")
        }
    }

    @Test("A conversation is direct only when it says so")
    func directIsCarriedNotGuessed() {
        let direct = room(named: "Sam", members: 2, isDirect: true)

        #expect(InboxScope.direct.includes(direct))
        #expect(!InboxScope.groups.includes(direct))
    }

    @Test("Every room is visible in at least one scope")
    func noRoomFallsBetweenTheTabs() {
        let all = [
            room(named: "Proof Room", members: 2),
            room(named: "Just me", members: 1),
            room(named: "Three of us", members: 3),
            room(named: "Sam", members: 2, isDirect: true),
        ]

        for one in all {
            let scopes = [InboxScope.everything, .direct, .groups].filter { $0.includes(one) }
            #expect(!scopes.isEmpty, "\(one.name) appears in no tab at all")
            #expect(InboxScope.everything.includes(one))
        }
    }

    @Test("A scope that filters everything out is still an empty list, not a blank screen")
    func filteredToNothingIsStillEmpty() {
        let rooms = [room(named: "Proof Room", members: 2)]
        let shown = rooms.filter(InboxScope.direct.includes)

        #expect(rooms.isEmpty == false)
        #expect(shown.isEmpty, "the setup for the bug: handed rooms, drawing none")
    }
}
