import Foundation

public enum DraftPlace: Hashable, Sendable {
    case room(ConversationID)
    case newPost
    case comment(PostID)

    public var isOutpost: Bool {
        if case .room = self { return false }
        return true
    }
}
