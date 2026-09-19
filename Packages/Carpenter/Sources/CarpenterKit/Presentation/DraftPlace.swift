import Foundation

public enum DraftPlace: Hashable, Sendable {
    case room(RoomID)
    case newPost
    case comment(PostID)

    public var isOutpost: Bool {
        if case .room = self { return false }
        return true
    }
}
