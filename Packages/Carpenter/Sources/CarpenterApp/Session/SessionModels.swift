import CarpenterKit
import CryptoKit
import Foundation

public struct RestoreAsk: Hashable, Sendable {
    public let request: RepairID
    public let person: ParticipantID
    public let personName: String
    public let room: RoomID?
    public let roomName: String

    public init(
        request: RepairID, person: ParticipantID, personName: String, room: RoomID?,
        roomName: String
    ) {
        self.request = request
        self.person = person
        self.personName = personName
        self.room = room
        self.roomName = roomName
    }
}

public struct IncomingPost: Hashable, Sendable {
    public let id: PostID
    public let author: ParticipantID
    public let authorName: String
    public let body: String
    public let postedAt: Date

    public init(
        id: PostID, author: ParticipantID, authorName: String, body: String, postedAt: Date
    ) {
        self.id = id
        self.author = author
        self.authorName = authorName
        self.body = body
        self.postedAt = postedAt
    }
}

public struct IncomingMessage: Hashable, Sendable {
    public let id: MessageID
    public let room: RoomID
    public let roomName: String
    public let author: String
    public let body: String
    public let sentAt: Date

    public init(
        id: MessageID, room: RoomID, roomName: String, author: String, body: String, sentAt: Date
    ) {
        self.id = id
        self.room = room
        self.roomName = roomName
        self.author = author
        self.body = body
        self.sentAt = sentAt
    }
}

public enum SyncMode: Hashable, Sendable {
    case full

    case readOnly
}

public enum AppSessionError: Error, Hashable, Sendable {
    case noIdentity
    case unknownRoom
    case cannotRevokeThisDevice
    case notAJoiningDevice
    case thatIsYou
    case nothingToSay
    case unknownMessage
    case readingOnly
    case cannotWriteThere
    case notYourMessage
    case tooLateToEdit
    case tooLateToWithdraw
    case tooManyPictures
    case tooBigToSend
    case keyNotRotated(rooms: Int)
    case protectionUnfinished
}

extension RoomsListOrganisation {
    mutating func forgetRoomsMissing(from present: Set<RoomID>) {
        for room in rooms.keys where !present.contains(room) {
            forget(room)
        }
    }
}

extension AppSession {
    public func mediaByteCount() async -> Int {
        (try? await storage.media.byteCount()) ?? 0
    }
}
