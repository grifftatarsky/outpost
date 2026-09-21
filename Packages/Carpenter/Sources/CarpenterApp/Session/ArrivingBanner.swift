import CarpenterKit
import Foundation

public struct BannerSender: Hashable, Sendable {
    public let id: ParticipantID
    public let name: String
    public let roomName: String
    public let isDirect: Bool
    public let threadID: String
    public let isAboutAPost: Bool

    public init(
        id: ParticipantID, name: String, roomName: String, isDirect: Bool, threadID: String,
        isAboutAPost: Bool
    ) {
        self.id = id
        self.name = name
        self.roomName = roomName
        self.isDirect = isDirect
        self.threadID = threadID
        self.isAboutAPost = isAboutAPost
    }
}

public struct ArrivingBanner: Hashable, Sendable {
    public let copy: NotificationCopy
    public let sender: BannerSender?
    public let quietly: Bool
    public let room: ConversationID?

    public init(copy: NotificationCopy, sender: BannerSender?, quietly: Bool, room: ConversationID? = nil) {
        self.copy = copy
        self.sender = sender
        self.quietly = quietly
        self.room = room
    }
}

public struct BannerSnapshot: Hashable, Sendable {
    public let post: PostID?
    public let ask: RepairID?
    public let message: MessageID?

    public init(post: PostID?, ask: RepairID?, message: MessageID?) {
        self.post = post
        self.ask = ask
        self.message = message
    }
}

public enum WhatArrived {
    public struct Surroundings: Sendable {
        public let filter: FocusFilter
        public let defaultLevel: NotificationLevel
        public let levelForRoom: @Sendable (ConversationID) -> NotificationLevel
        public let isDirect: @Sendable (ConversationID) -> Bool
        public let authorOfMessage: @Sendable (ConversationID, MessageID) -> Member?

        public init(
            filter: FocusFilter,
            defaultLevel: NotificationLevel,
            levelForRoom: @escaping @Sendable (ConversationID) -> NotificationLevel,
            isDirect: @escaping @Sendable (ConversationID) -> Bool = { _ in false },
            authorOfMessage: @escaping @Sendable (ConversationID, MessageID) -> Member? = { _, _ in nil }
        ) {
            self.filter = filter
            self.defaultLevel = defaultLevel
            self.levelForRoom = levelForRoom
            self.isDirect = isDirect
            self.authorOfMessage = authorOfMessage
        }
    }

    public static func since(
        _ before: BannerSnapshot,
        post: IncomingPost?,
        ask: RestoreAsk?,
        message: IncomingMessage?,
        in world: Surroundings
    ) -> ArrivingBanner? {
        if let post, post.id != before.post {
            let level = world.filter.levelForAPost(own: world.defaultLevel)
            let copy = MessageNotification.ofPost(
                author: post.author, name: post.authorName, body: post.body, level: level)
            return ArrivingBanner(
                copy: copy,
                sender: copy.isGeneric
                    ? nil
                    : BannerSender(
                        id: post.author, name: post.authorName, roomName: "", isDirect: true,
                        threadID: copy.threadID, isAboutAPost: true),
                quietly: false)
        }

        if let ask, ask.request != before.ask {
            return ArrivingBanner(
                copy: RestoreNotification.ofAsk(
                    person: ask.person, name: ask.personName, roomName: ask.roomName,
                    level: world.defaultLevel),
                sender: nil, quietly: false)
        }

        guard let message, message.id != before.message else { return nil }

        let level = world.filter.level(
            for: message.room, own: world.levelForRoom(message.room))
        let copy = MessageNotification.of(
            room: message.room, roomName: message.roomName, author: message.author,
            body: message.body, level: level)

        var sender: BannerSender?
        if level.showsSender, !copy.isGeneric,
            let author = world.authorOfMessage(message.room, message.id)
        {
            sender = BannerSender(
                id: author.id, name: author.displayName, roomName: message.roomName,
                isDirect: world.isDirect(message.room), threadID: copy.threadID,
                isAboutAPost: false)
        }

        return ArrivingBanner(
            copy: copy, sender: sender, quietly: !world.filter.allows(message.room),
            room: message.room)
    }
}
