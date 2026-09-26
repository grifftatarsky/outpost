import CarpenterKit
import SwiftUI

public enum InboxScope: Sendable {
    case everything
    case direct
    case groups

    // COPY BEGIN 6aaef16e [NEEDS HUMAN REVIEW]
    var title: LocalizedStringResource {
        switch self {
        case .everything: .module("Messages")
        case .direct: .module("Solos")
        case .groups: .module("Rooms")
        }
    }
    // COPY END 6aaef16e

    func includes(_ room: RoomSummary) -> Bool {
        switch self {
        case .everything: true
        case .direct: room.isDirect
        case .groups: !room.isDirect
        }
    }

    var marksGroups: Bool { self == .everything }

    // COPY BEGIN cba8260c [NEEDS HUMAN REVIEW]
    var searchPrompt: LocalizedStringResource {
        switch self {
        case .everything: .module("Search conversations")
        case .direct: .module("Search solos")
        case .groups: .module("Search rooms")
        }
    }
    // COPY END cba8260c

    // COPY BEGIN f14426f1 [NEEDS HUMAN REVIEW]
    var emptyTitle: LocalizedStringResource {
        switch self {
        case .everything: .module("No conversations yet")
        case .direct: .module("No solos yet")
        case .groups: .module("No rooms yet")
        }
    }
    // COPY END f14426f1

    // COPY BEGIN 11529a89 [NEEDS HUMAN REVIEW]
    var emptyDescription: LocalizedStringResource {
        switch self {
        case .everything:
            .module(
                "A solo is a conversation with one person; a room is one you share with everyone you invite. Nobody can look you up, so nothing arrives here until you send a solo, make a room, or accept an invitation.")
        case .groups:
            .module(
                "A room is a conversation you share with people you invite. Nobody can look you up, so nothing arrives here until you make a room or accept an invitation.")
        case .direct:
            .module(
                "A solo is a conversation with one other person. Anything with more people is a room, and lives under Rooms.")
        }
    }
    // COPY END 11529a89
}
