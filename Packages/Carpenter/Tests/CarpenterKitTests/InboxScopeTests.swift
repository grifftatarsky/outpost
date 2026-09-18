import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterUI

@Suite struct DirectConversationTests {
    private func room(_ members: Int, isDirect: Bool = false) -> RoomSummary {
        RoomSummary(
            name: "R", memberCount: members, lastAuthor: nil, lastMessage: "",
            lastActivity: .now, hasUnread: false, isDirect: isDirect)
    }

    @Test("Direct is carried, not counted")
    func directIsCarriedNotCounted() {
        #expect(room(1).isDirect == false)
        #expect(room(2).isDirect == false, "two people in a room is a room")
        #expect(room(3).isDirect == false)
        #expect(room(12).isDirect == false)
        #expect(room(2, isDirect: true).isDirect)
    }

    @Test("Each scope carries exactly its own kind, and the merged one carries both")
    func scopesPartition() {
        let direct = room(2, isDirect: true)
        let group = room(6)

        #expect(InboxScope.direct.includes(direct))
        #expect(InboxScope.direct.includes(group) == false)
        #expect(InboxScope.groups.includes(group))
        #expect(InboxScope.groups.includes(direct) == false)
        #expect(InboxScope.everything.includes(direct))
        #expect(InboxScope.everything.includes(group))
    }

    @Test("Each list is named for what it holds")
    func titlesNameTheirContents() {
        #expect(String(localized: InboxScope.everything.title) == "Messages")
        #expect(String(localized: InboxScope.direct.title) == "Solos")
        #expect(String(localized: InboxScope.groups.title) == "Rooms")
    }

    @Test("Groups are marked only where both kinds share a list")
    func marksOnlyWhereItDistinguishes() {
        #expect(InboxScope.everything.marksGroups)
        #expect(InboxScope.groups.marksGroups == false)
        #expect(InboxScope.direct.marksGroups == false)
    }
}

@MainActor
@Suite struct DemoDirectConversationTests {
    @Test("The demo direct room is a two-person conversation and reads as one")
    func demoDirectIsDirect() {
        let room = DemoConversation.directRoom()
        #expect(room.isDirect)
        #expect(room.memberCount == 2)
        #expect(InboxScope.direct.includes(room))
    }

    @Test("Its transcript is between exactly two people, one of them the viewer")
    func twoSpeakers() {
        let messages = DemoConversation.directMessages()
        #expect(!messages.isEmpty)
        #expect(Set(messages.map(\.author.id)).count == 2)
        #expect(messages.contains { $0.isMine })
        let times = messages.map(\.sentAt)
        #expect(times == times.sorted())
    }
}
