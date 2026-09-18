import Foundation

public struct SearchResults: Hashable, Sendable {
    public struct Conversation: Hashable, Sendable, Identifiable {
        public let room: RoomID
        public let name: String
        public let isDirect: Bool
        public var id: RoomID { room }

        public init(room: RoomID, name: String, isDirect: Bool) {
            self.room = room
            self.name = name
            self.isDirect = isDirect
        }
    }

    public struct Said: Hashable, Sendable, Identifiable {
        public let message: MessageID
        public let room: RoomID
        public let roomName: String
        public let author: Member
        public let body: String
        public let sentAt: Date
        public var id: MessageID { message }

        public init(
            message: MessageID, room: RoomID, roomName: String, author: Member, body: String,
            sentAt: Date
        ) {
            self.message = message
            self.room = room
            self.roomName = roomName
            self.author = author
            self.body = body
            self.sentAt = sentAt
        }
    }

    public struct Picture: Hashable, Sendable, Identifiable {
        public let message: MessageID
        public let room: RoomID
        public let roomName: String
        public let author: Member
        public let caption: String
        public let media: MediaAttachment
        public let sentAt: Date
        public var id: MessageID { message }

        public init(
            message: MessageID, room: RoomID, roomName: String, author: Member, caption: String,
            media: MediaAttachment, sentAt: Date
        ) {
            self.message = message
            self.room = room
            self.roomName = roomName
            self.author = author
            self.caption = caption
            self.media = media
            self.sentAt = sentAt
        }
    }

    public var conversations: [Conversation]
    public var said: [Said]
    public var pictures: [Picture]
    public var posts: [OutpostPost]

    public var isEmpty: Bool {
        conversations.isEmpty && said.isEmpty && pictures.isEmpty && posts.isEmpty
    }

    public init(
        conversations: [Conversation] = [], said: [Said] = [], pictures: [Picture] = [],
        posts: [OutpostPost] = []
    ) {
        self.conversations = conversations
        self.said = said
        self.pictures = pictures
        self.posts = posts
    }
}
