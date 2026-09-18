import Foundation

public struct BadgeChoices: Hashable, Sendable, Codable {
    public var messages: Bool
    public var outposts: Bool

    public static let `default` = BadgeChoices(messages: true, outposts: true)

    public enum Meaning: Hashable, Sendable {
        case both, outpostsOnly, messagesOnly, off
    }

    public var meaning: Meaning {
        switch (messages, outposts) {
        case (true, true): return .both
        case (false, true): return .outpostsOnly
        case (true, false): return .messagesOnly
        case (false, false): return .off
        }
    }

    public init(messages: Bool, outposts: Bool) {
        self.messages = messages
        self.outposts = outposts
    }
}

public enum NewPostNotifications: String, CaseIterable, Sendable, Codable {
    case none, each, all
}

public struct OutpostNotificationChoices: Hashable, Sendable, Codable {
    public var newPosts: NewPostNotifications
    public var repliesOnPostsICommentedOn: Bool
    public var repliesOnPostsIReactedTo: Bool
    public var commentsOnMyPosts: Bool
    public var likesOnMyPosts: Bool

    public static let `default` = OutpostNotificationChoices(
        newPosts: .each, repliesOnPostsICommentedOn: true, repliesOnPostsIReactedTo: false,
        commentsOnMyPosts: true, likesOnMyPosts: false)

    public static let none = OutpostNotificationChoices(
        newPosts: .none, repliesOnPostsICommentedOn: false, repliesOnPostsIReactedTo: false,
        commentsOnMyPosts: false, likesOnMyPosts: false)

    public enum Kind: String, CaseIterable, Sendable {
        case repliesOnPostsICommentedOn, repliesOnPostsIReactedTo, commentsOnMyPosts, likesOnMyPosts

        public var interruption: NotificationUrgency {
            switch self {
            case .commentsOnMyPosts, .repliesOnPostsICommentedOn, .repliesOnPostsIReactedTo:
                return .active
            case .likesOnMyPosts: return .passive
            }
        }

        public var path: WritableKeyPath<OutpostNotificationChoices, Bool> {
            switch self {
            case .repliesOnPostsICommentedOn: return \.repliesOnPostsICommentedOn
            case .repliesOnPostsIReactedTo: return \.repliesOnPostsIReactedTo
            case .commentsOnMyPosts: return \.commentsOnMyPosts
            case .likesOnMyPosts: return \.likesOnMyPosts
            }
        }
    }

    public func wants(_ kind: Kind) -> Bool { self[keyPath: kind.path] }

    public var wantedCount: Int {
        Kind.allCases.count { wants($0) } + (newPosts == .none ? 0 : 1)
    }

    public var wantsAnything: Bool { wantedCount > 0 }

    public init(
        newPosts: NewPostNotifications, repliesOnPostsICommentedOn: Bool,
        repliesOnPostsIReactedTo: Bool, commentsOnMyPosts: Bool, likesOnMyPosts: Bool
    ) {
        self.newPosts = newPosts
        self.repliesOnPostsICommentedOn = repliesOnPostsICommentedOn
        self.repliesOnPostsIReactedTo = repliesOnPostsIReactedTo
        self.commentsOnMyPosts = commentsOnMyPosts
        self.likesOnMyPosts = likesOnMyPosts
    }
}

public enum NotificationUrgency: Sendable {
    case passive
    case active
}
