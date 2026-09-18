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
    case keyNotTurned(rooms: Int)
}

extension RoomsListOrganisation {
    mutating func forgetRoomsMissing(from present: Set<RoomID>) {
        for room in rooms.keys where !present.contains(room) {
            forget(room)
        }
    }
}

extension Data {
    var uuidValue: uuid_t {
        var bytes = Array(prefix(16))
        bytes.append(contentsOf: Array(repeating: 0, count: Swift.max(0, 16 - bytes.count)))
        return (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
    }
}

extension AppSession {
    public func mediaByteCount() async -> Int {
        (try? await storage.media.byteCount()) ?? 0
    }
}
