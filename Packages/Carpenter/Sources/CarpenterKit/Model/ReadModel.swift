import Foundation

public struct RoomID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public static func outpost(of participant: ParticipantID) -> RoomID {
        var bytes = Array(participant.rawValue.prefix(16))
        bytes.append(contentsOf: Array(repeating: 0, count: Swift.max(0, 16 - bytes.count)))
        return RoomID(
            rawValue: UUID(
                uuid: (
                    bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                    bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14],
                    bytes[15]
                )))
    }
}

public enum RoomDeletion: Hashable, Sendable {
    case allowed
    case stillIn
    case departureNotSent
}

public enum RoomStanding: Hashable, Sendable {
    case present
    case removed(by: Member)
    case left

    public var mayWrite: Bool { self == .present }
}

public struct ViewedItem: Identifiable, Hashable, Sendable {
    public let entry: EntryHash
    public let author: Member
    public let words: String
    public let at: Date
    public let isMine: Bool
    public let isMedia: Bool

    public var id: EntryHash { entry }

    public init(
        entry: EntryHash, author: Member, words: String, at: Date, isMine: Bool, isMedia: Bool
    ) {
        self.entry = entry
        self.author = author
        self.words = words
        self.at = at
        self.isMine = isMine
        self.isMedia = isMedia
    }

    public init(_ message: Message) {
        self.init(
            entry: message.id.entry, author: message.author, words: message.body,
            at: message.sentAt, isMine: message.isMine, isMedia: message.media != nil)
    }

    public init(_ post: OutpostPost) {
        self.init(
            entry: post.id.entry, author: post.author, words: post.body, at: post.postedAt,
            isMine: post.isMine, isMedia: !post.media.isEmpty)
    }

    public init(_ comment: OutpostComment) {
        self.init(
            entry: comment.id.entry, author: comment.author, words: comment.body,
            at: comment.postedAt, isMine: comment.isMine, isMedia: false)
    }
}

public struct MessageID: Hashable, Sendable, Codable {
    public let entry: EntryHash

    public init(entry: EntryHash) {
        self.entry = entry
    }
}

public struct PostID: Hashable, Sendable, Codable {
    public let entry: EntryHash

    public init(entry: EntryHash) {
        self.entry = entry
    }
}

public struct Member: Identifiable, Hashable, Sendable {
    public let id: ParticipantID
    public let displayName: String

    public let isPlaceholder: Bool

    public let isAnonymous: Bool

    public init(
        id: ParticipantID, displayName: String, isPlaceholder: Bool = false,
        isAnonymous: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.isPlaceholder = isPlaceholder
        self.isAnonymous = isAnonymous
    }

    public static func anonymous(_ persona: AnonPersona) -> Member {
        Member(id: .anonymous, displayName: persona.displayName, isAnonymous: true)
    }

    public var initials: String {
        isPlaceholder ? String(displayName.prefix(2)).uppercased() : AvatarInitials.of(displayName)
    }
}

public struct RoomSummary: Identifiable, Hashable, Sendable {
    public let id: RoomID
    public let name: String
    public let memberCount: Int
    public let lastAuthor: Member?
    public let lastMessage: String
    public let lastActivity: Date
    public let hasUnread: Bool

    public init(
        id: RoomID = RoomID(),
        name: String,
        memberCount: Int,
        lastAuthor: Member?,
        lastMessage: String,
        lastActivity: Date,
        hasUnread: Bool,
        isDirect: Bool = false,
        initials: String? = nil,
        partner: ParticipantID? = nil
    ) {
        self.id = id
        self.name = name
        self.memberCount = memberCount
        self.lastAuthor = lastAuthor
        self.lastMessage = lastMessage
        self.lastActivity = lastActivity
        self.hasUnread = hasUnread
        self.isDirect = isDirect
        self.personInitials = initials
        self.partner = partner
    }

    public let partner: ParticipantID?

    public var initials: String { personInitials ?? AvatarInitials.of(name) }

    private let personInitials: String?

    public let isDirect: Bool
}

public struct MediaAttachment: Hashable, Sendable {
    public let reference: AttachmentReference
    public let kind: MediaKind
    public let width: Int
    public let height: Int
    public let preview: Data?
    public let duration: TimeInterval?

    public init(
        reference: AttachmentReference, kind: MediaKind, width: Int, height: Int, preview: Data?,
        duration: TimeInterval? = nil
    ) {
        self.reference = reference
        self.kind = kind
        self.width = width
        self.height = height
        self.preview = preview
        self.duration = duration
    }

    public init(_ body: MediaBody) {
        self.init(
            reference: body.attachment, kind: body.kind, width: body.width, height: body.height,
            preview: body.preview, duration: body.duration)
    }

    public var aspectRatio: Double {
        guard width > 0, height > 0 else { return 1 }
        return Double(width) / Double(height)
    }

    public var id: AttachmentID { reference.id }
}

public struct Message: Identifiable, Hashable, Sendable {
    public let id: MessageID
    public let author: Member
    public let body: String
    public let sentAt: Date
    public let isMine: Bool

    public let delivery: DeliveryState

    public let editedAt: Date?

    public let isWithdrawn: Bool

    public let revisions: [Revision]

    public let reactions: [String: Set<ParticipantID>]

    public let myReaction: String?

    public let media: MediaAttachment?

    public let notGone: NotGone?

    public var isEdited: Bool { editedAt != nil }

    public var preview: String {
        if body.isEmpty, let media { return MediaBody.line(for: media.kind) }
        return body
    }

    public init(
        id: MessageID,
        author: Member,
        body: String,
        sentAt: Date,
        isMine: Bool,
        delivery: DeliveryState = .pending,
        editedAt: Date? = nil,
        reactions: [String: Set<ParticipantID>] = [:],
        myReaction: String? = nil,
        isWithdrawn: Bool = false,
        revisions: [Revision] = [],
        media: MediaAttachment? = nil,
        notGone: NotGone? = nil
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.sentAt = sentAt
        self.isMine = isMine
        self.delivery = delivery
        self.editedAt = editedAt
        self.reactions = reactions
        self.myReaction = myReaction
        self.isWithdrawn = isWithdrawn
        self.revisions = revisions
        self.media = media
        self.notGone = notGone
    }

    public func noting(_ notGone: NotGone?) -> Message {
        Message(
            id: id, author: author, body: body, sentAt: sentAt, isMine: isMine, delivery: delivery,
            editedAt: editedAt, reactions: reactions, myReaction: myReaction,
            isWithdrawn: isWithdrawn, revisions: revisions, media: media, notGone: notGone)
    }
}

public struct OutpostComment: Identifiable, Hashable, Sendable {
    public let id: PostID
    public let author: Member
    public let body: String
    public let postedAt: Date
    public let reactions: [String: Set<ParticipantID>]
    public let isMine: Bool
    public let editedAt: Date?
    public let isWithdrawn: Bool

    public init(
        id: PostID,
        author: Member,
        body: String,
        postedAt: Date = .distantPast,
        reactions: [String: Set<ParticipantID>] = [:],
        isMine: Bool = false,
        editedAt: Date? = nil,
        isWithdrawn: Bool = false
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.postedAt = postedAt
        self.reactions = reactions
        self.isMine = isMine
        self.editedAt = editedAt
        self.isWithdrawn = isWithdrawn
    }
}

public struct OutpostPost: Identifiable, Hashable, Sendable {
    public let id: PostID
    public let author: Member
    public let body: String
    public let postedAt: Date
    public let commentCount: Int

    public let previewComments: [OutpostComment]

    public let reactions: [String: Set<ParticipantID>]

    public let isMine: Bool

    public let media: [MediaAttachment]

    public let editedAt: Date?

    public let isWithdrawn: Bool

    public init(
        id: PostID,
        author: Member,
        body: String,
        postedAt: Date,
        commentCount: Int,
        previewComments: [OutpostComment] = [],
        reactions: [String: Set<ParticipantID>] = [:],
        isMine: Bool = false,
        media: [MediaAttachment] = [],
        editedAt: Date? = nil,
        isWithdrawn: Bool = false
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.postedAt = postedAt
        self.commentCount = commentCount
        self.previewComments = previewComments
        self.reactions = reactions
        self.isMine = isMine
        self.media = media
        self.editedAt = editedAt
        self.isWithdrawn = isWithdrawn
    }
}

public struct RoomGreeting: Identifiable, Hashable, Sendable {
    public let id: RoomID
    public let name: String
    public let invitedBy: Member?
    public let members: [Member]
    public let access: RoomAccess
    public let isDirect: Bool

    public init(
        id: RoomID, name: String, invitedBy: Member?, members: [Member], access: RoomAccess,
        isDirect: Bool = false
    ) {
        self.id = id
        self.name = name
        self.invitedBy = invitedBy
        self.members = members
        self.access = access
        self.isDirect = isDirect
    }
}

public struct AwaitingAdmission: Identifiable, Hashable, Sendable {
    public let room: RoomID
    public let invitedBy: Member
    public let phrase: String?
    public let confirmedAt: Date
    public let expiresAt: Date

    public let hasLapsed: Bool

    public var id: RoomID { room }

    public var isIndefinite: Bool { expiresAt >= .distantFuture }

    public init(
        room: RoomID, invitedBy: Member, phrase: String?, confirmedAt: Date, expiresAt: Date,
        hasLapsed: Bool = false
    ) {
        self.room = room
        self.invitedBy = invitedBy
        self.phrase = phrase
        self.confirmedAt = confirmedAt
        self.expiresAt = expiresAt
        self.hasLapsed = hasLapsed
    }
}
