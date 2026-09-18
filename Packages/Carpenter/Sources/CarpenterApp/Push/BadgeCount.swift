import CarpenterKit
import Foundation

public enum BadgeCount {
    public static func of(
        _ rooms: [RoomSummary],
        outposts unseenWalls: Int = 0,
        choices: BadgeChoices = .default
    ) -> Int {
        let conversations = choices.messages ? rooms.count(where: \.hasUnread) : 0
        let walls = choices.outposts ? unseenWalls : 0
        return conversations + walls
    }
}
