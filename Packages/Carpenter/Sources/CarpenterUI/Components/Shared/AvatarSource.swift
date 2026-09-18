import CarpenterKit

public enum AvatarSource: Hashable, Sendable {
    case own
    case ownOutpost
    case chosen
    case outpost
    case rooms
    case monogram
}

public func avatarSource(
    isViewer: Bool,
    onOutpost: Bool,
    hasOwn: Bool,
    hasOwnOutpost: Bool,
    hasChosen: Bool,
    hasOutpost: Bool,
    hasRooms: Bool
) -> AvatarSource {
    if isViewer {
        if onOutpost { return hasOwnOutpost ? .ownOutpost : .monogram }
        return hasOwn ? .own : .monogram
    }
    if hasChosen { return .chosen }
    if onOutpost {
        if hasOutpost { return .outpost }
        if hasRooms { return .rooms }
    } else {
        if hasRooms { return .rooms }
        if hasOutpost { return .outpost }
    }
    return .monogram
}
