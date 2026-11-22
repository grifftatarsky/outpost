import CarpenterKit
import Foundation

public struct ArrivingBanner: Hashable, Sendable {
    public let copy: NotificationCopy
    public let quietly: Bool

    public init(copy: NotificationCopy, quietly: Bool) {
        self.copy = copy
        self.quietly = quietly
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
        public let levelForRoom: @Sendable (RoomID) -> NotificationLevel

        public init(
            filter: FocusFilter,
            defaultLevel: NotificationLevel,
            levelForRoom: @escaping @Sendable (RoomID) -> NotificationLevel
        ) {
            self.filter = filter
            self.defaultLevel = defaultLevel
            self.levelForRoom = levelForRoom
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
            return ArrivingBanner(copy: copy, quietly: false)
        }

        if let ask, ask.request != before.ask {
            return ArrivingBanner(
                copy: RestoreNotification.ofAsk(
                    person: ask.person, name: ask.personName, roomName: ask.roomName,
                    level: world.defaultLevel),
                quietly: false)
        }

        guard let message, message.id != before.message else { return nil }

        let level = world.filter.level(
            for: message.room, own: world.levelForRoom(message.room))
        let copy = MessageNotification.of(
            room: message.room, roomName: message.roomName, author: message.author,
            body: message.body, level: level)

        return ArrivingBanner(copy: copy, quietly: !world.filter.allows(message.room))
    }
}
