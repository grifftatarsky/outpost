import Foundation

public struct PhotoRequest: Identifiable, Hashable, Sendable {
    public struct ID: Hashable, Sendable {
        public let person: ParticipantID
        public let attachment: AttachmentID

        public init(person: ParticipantID, attachment: AttachmentID) {
            self.person = person
            self.attachment = attachment
        }
    }

    public let person: Member
    public let sender: ParticipantID
    public let media: MediaAttachment
    public let message: MessageID
    public let room: RoomID
    public let askedAt: Date

    public init(
        person: Member, sender: ParticipantID, media: MediaAttachment, message: MessageID, room: RoomID,
        askedAt: Date
    ) {
        self.person = person
        self.sender = sender
        self.media = media
        self.message = message
        self.room = room
        self.askedAt = askedAt
    }

    public var id: ID { ID(person: person.id, attachment: media.id) }
}
