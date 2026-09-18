import Foundation

public enum RenderedContent: Hashable, Sendable {
    case text(String)

    case sealed

    case withdrawn

    case unrenderable(type: PayloadType, fallback: String?)

    case media(MediaBody)
}

public struct RenderedEntry: Identifiable, Hashable, Sendable {
    public let id: EntryHash

    public let type: PayloadType

    public let author: ParticipantID
    public let device: DeviceID
    public let wallTime: Date
    public let room: RoomID?
    public var content: RenderedContent
    public var editedAt: Date?

    public var replyingTo: EntryHash?

    public var reactions: [String: Set<ParticipantID>]

    public var revisions: [Revision] = []

    public var roomKind: RoomKind? = nil

    public var memberPhoto: MemberPhotoBody? = nil

    public var focusStatus: FocusStatusBody? = nil

    public var supporterBadge: SupporterBadgeBody? = nil

    public var seq: UInt64 = 0
    public var clock: VectorClock = VectorClock()

    public var feedKey: FeedKey { FeedKey(author: author, device: device) }

    public var isEdited: Bool { editedAt != nil }
}

public struct Revision: Hashable, Sendable {
    public let text: String
    public let at: Date

    public init(text: String, at: Date) {
        self.text = text
        self.at = at
    }
}

public enum Fold {
    public static func render(_ entries: [Entry], using chain: EpochChain) -> [RenderedEntry] {
        render(entries) { $0.opened(using: chain) }
    }

    public static func render(
        _ entries: [Entry], opening: (Entry) -> Payload?
    ) -> [RenderedEntry] {
        var rendered: [EntryHash: RenderedEntry] = [:]
        var order: [EntryHash] = []
        var withdrawn: Set<EntryHash> = []

        for entry in CausalOrder.sorted(entries) {
            guard let payload = opening(entry) else {
                order.append(entry.hash)
                rendered[entry.hash] = RenderedEntry(
                    id: entry.hash, type: .post, author: entry.author, device: entry.device,
                    wallTime: entry.wallTime, room: entry.room, content: .sealed,
                    editedAt: nil, replyingTo: nil, reactions: [:],
                    seq: entry.seq, clock: entry.clock)
                continue
            }

            switch payload.type {
            case .post, .roomProfile, .memberProfile, .comment, .media, .memberPhoto, .focusStatus,
                .supporterBadge:
                order.append(entry.hash)
                var made = RenderedEntry(
                    id: entry.hash,
                    type: payload.type,
                    author: entry.author,
                    device: entry.device,
                    wallTime: entry.wallTime,
                    room: entry.room,
                    content: content(of: payload),
                    editedAt: nil,
                    replyingTo: (try? payload.decode(CommentBody.self))?.target,
                    reactions: [:],
                    seq: entry.seq,
                    clock: entry.clock
                )
                if payload.type == .roomProfile {
                    made.roomKind = (try? payload.decode(RoomProfileBody.self))?.kind
                }
                if payload.type == .memberPhoto {
                    made.memberPhoto = try? payload.decode(MemberPhotoBody.self)
                }
                if payload.type == .focusStatus {
                    made.focusStatus = try? payload.decode(FocusStatusBody.self)
                }
                if payload.type == .supporterBadge {
                    made.supporterBadge = try? payload.decode(SupporterBadgeBody.self)
                }
                rendered[entry.hash] = made

            case .edit:
                guard let body = try? payload.decode(EditBody.self),
                    var target = rendered[body.target],
                    target.author == entry.author,
                    !withdrawn.contains(body.target),
                    { if case .text = target.content { true } else { false } }(),
                    Editing.isOpen(at: entry.wallTime, for: target.wallTime, within: Editing.editWindow)
                else { continue }

                if target.revisions.isEmpty, case .text(let original) = target.content {
                    target.revisions.append(Revision(text: original, at: target.wallTime))
                }
                target.revisions.append(Revision(text: body.text, at: entry.wallTime))
                target.content = .text(body.text)
                target.editedAt = entry.wallTime
                rendered[body.target] = target

            case .tombstone:
                guard let body = try? payload.decode(TombstoneBody.self),
                    var target = rendered[body.target],
                    target.author == entry.author,
                    Editing.isOpen(
                        at: entry.wallTime, for: target.wallTime, within: Editing.withdrawWindow)
                else { continue }

                target.content = .withdrawn
                target.revisions = []
                rendered[body.target] = target
                withdrawn.insert(body.target)

            case .reaction:
                guard let body = try? payload.decode(ReactionBody.self),
                    var target = rendered[body.target]
                else { continue }

                for emoji in target.reactions.keys {
                    target.reactions[emoji]?.remove(entry.author)
                    if target.reactions[emoji]?.isEmpty == true { target.reactions[emoji] = nil }
                }
                if let emoji = body.emoji {
                    target.reactions[emoji, default: []].insert(entry.author)
                }
                rendered[body.target] = target

            default:
                order.append(entry.hash)
                rendered[entry.hash] = RenderedEntry(
                    id: entry.hash,
                    type: payload.type,
                    author: entry.author,
                    device: entry.device,
                    wallTime: entry.wallTime,
                    room: entry.room,
                    content: .unrenderable(type: payload.type, fallback: payload.fallbackText),
                    editedAt: nil,
                    replyingTo: nil,
                    reactions: [:],
                    seq: entry.seq,
                    clock: entry.clock
                )
            }
        }

        return order.compactMap { rendered[$0] }
    }

    private static func content(of payload: Payload) -> RenderedContent {
        switch payload.type {
        case .comment:
            guard let body = try? payload.decode(CommentBody.self) else { break }
            return .text(body.text)
        case .roomProfile:
            guard let body = try? payload.decode(RoomProfileBody.self) else { break }
            return .text(body.name)
        case .memberProfile:
            guard let body = try? payload.decode(MemberProfileBody.self) else { break }
            return .text(body.name ?? "")
        case .media:
            guard let body = try? payload.decode(MediaBody.self) else { break }
            return .media(body)
        default:
            guard let body = try? payload.decode(PostBody.self) else { break }
            return .text(body.text)
        }
        return .unrenderable(type: payload.type, fallback: payload.fallbackText)
    }
}
