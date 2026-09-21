import CarpenterKit
import Foundation
import Testing

@Suite("What the badge should say")
struct BadgeCountTests {
    private func room(unread: Bool) -> RoomSummary {
        RoomSummary(
            id: ConversationID.room(UUID()), name: "Kitchen", memberCount: 2, lastAuthor: nil,
            lastMessage: "", lastActivity: Date(timeIntervalSince1970: 1_786_635_000),
            hasUnread: unread)
    }

    @Test("Nothing unread means nothing on the icon")
    func nothingUnreadIsZero() {
        #expect(BadgeCount.of([]) == 0)
        #expect(BadgeCount.of([room(unread: false), room(unread: false)]) == 0)
    }

    @Test("Rooms with something unread are counted, and only those")
    func countsOnlyUnreadRooms() {
        #expect(BadgeCount.of([room(unread: true)]) == 1)
        #expect(BadgeCount.of([room(unread: true), room(unread: false), room(unread: true)]) == 2)
    }

    // MARK: The four sentences the Notifications screen shows a member

    private let both = BadgeChoices(messages: true, outposts: true)
    private let outpostsOnly = BadgeChoices(messages: false, outposts: true)
    private let messagesOnly = BadgeChoices(messages: true, outposts: false)
    private let off = BadgeChoices(messages: false, outposts: false)

    private var twoUnreadRooms: [RoomSummary] { [room(unread: true), room(unread: true), room(unread: false)] }

    @Test("Both: unread conversations and Outposts with something new")
    func bothCountsEverything() {
        #expect(BadgeCount.of(twoUnreadRooms, outposts: 3, choices: both) == 5)
    }

    @Test("Outposts only: Outposts with something new, and nothing else")
    func outpostsOnlyIgnoresRooms() {
        #expect(
            BadgeCount.of(twoUnreadRooms, outposts: 3, choices: outpostsOnly) == 3,
            "the icon counted conversations at a setting whose own sentence says it counts none")
    }

    @Test("Messages only: unread conversations, and nothing else")
    func messagesOnlyIgnoresOutposts() {
        #expect(BadgeCount.of(twoUnreadRooms, outposts: 3, choices: messagesOnly) == 2)
    }

    @Test("Off: no number at all")
    func offIsZero() {
        #expect(
            BadgeCount.of(twoUnreadRooms, outposts: 3, choices: off) == 0,
            "the icon showed a number at the setting whose own sentence says it shows none")
    }

    @Test("Every setting's sentence is true of the number it produces")
    func everySentenceHolds() {
        let rooms = twoUnreadRooms
        let unreadRooms = rooms.count(where: \.hasUnread)
        let walls = 3

        for choices in [both, outpostsOnly, messagesOnly, off] {
            let count = BadgeCount.of(rooms, outposts: walls, choices: choices)
            let countsRooms = count >= unreadRooms && choices.messages
            let countsWalls = count >= walls && choices.outposts

            #expect(
                countsRooms == choices.messages,
                "\(choices.meaning) disagrees with its own sentence about conversations")
            #expect(
                countsWalls == choices.outposts,
                "\(choices.meaning) disagrees with its own sentence about Outposts")
        }
    }

    @Test("A member with nothing new sees no number, whatever the setting")
    func quietIsQuietAtEverySetting() {
        for choices in [both, outpostsOnly, messagesOnly, off] {
            #expect(BadgeCount.of([room(unread: false)], outposts: 0, choices: choices) == 0)
        }
    }
}
