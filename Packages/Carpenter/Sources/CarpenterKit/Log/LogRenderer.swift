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

public enum RenderStep: Sendable {
    case shows(RenderedEntry)
    case edits(EditBody)
    case withdraws(TombstoneBody)
    case reacts(ReactionBody)
    case nothing
}

public enum LogRenderer {
    public static func render(_ entries: [Entry], using chain: EpochChain) -> [RenderedEntry] {
        render(entries) { $0.opened(using: chain) }
    }

    public static func render(
        _ entries: [Entry], opening: (Entry) -> Payload?
    ) -> [RenderedEntry] {
        render(entries, reading: { step(for: $0, payload: opening($0)) })
    }

    public static func render(
        _ entries: [Entry], reading: (Entry) -> RenderStep
    ) -> [RenderedEntry] {
        var rendered: [RenderedEntry] = []
        var position: [EntryHash: Int] = [:]
        var withdrawn: Set<EntryHash> = []

        for entry in CausalOrder.sorted(entries) {
            switch reading(entry) {
            case .shows(let made):
                position[made.id] = rendered.count
                rendered.append(made)

            case .edits(let body):
                guard let at = position[body.target],
                    rendered[at].author == entry.author,
                    !withdrawn.contains(body.target),
                    { if case .text = rendered[at].content { true } else { false } }(),
                    Editing.isOpen(at: entry.wallTime, for: rendered[at].wallTime, within: Editing.editWindow)
                else { continue }

                if rendered[at].revisions.isEmpty, case .text(let original) = rendered[at].content {
                    rendered[at].revisions.append(Revision(text: original, at: rendered[at].wallTime))
                }
                rendered[at].revisions.append(Revision(text: body.text, at: entry.wallTime))
                rendered[at].content = .text(body.text)
                rendered[at].editedAt = entry.wallTime

            case .withdraws(let body):
                guard let at = position[body.target],
                    rendered[at].author == entry.author,
                    Editing.isOpen(
                        at: entry.wallTime, for: rendered[at].wallTime, within: Editing.withdrawWindow)
                else { continue }

                rendered[at].content = .withdrawn
                rendered[at].revisions = []
                withdrawn.insert(body.target)

            case .reacts(let body):
                guard let at = position[body.target] else { continue }

                for emoji in rendered[at].reactions.keys {
                    rendered[at].reactions[emoji]?.remove(entry.author)
                    if rendered[at].reactions[emoji]?.isEmpty == true { rendered[at].reactions[emoji] = nil }
                }
                if let emoji = body.emoji {
                    rendered[at].reactions[emoji, default: []].insert(entry.author)
                }

            case .nothing:
                continue
            }
        }

        return rendered
    }

    public static func step(for entry: Entry, payload: Payload?) -> RenderStep {
        guard let payload else {
            return .shows(
                RenderedEntry(
                    id: entry.hash, type: .post, author: entry.author, device: entry.device,
                    wallTime: entry.wallTime, room: entry.room, content: .sealed,
                    editedAt: nil, replyingTo: nil, reactions: [:],
                    seq: entry.seq, clock: entry.clock))
        }

        switch payload.type {
        case .post, .roomProfile, .memberProfile, .comment, .media, .memberPhoto, .focusStatus,
            .supporterBadge:
            let comment = payload.type == .comment ? try? payload.decode(CommentBody.self) : nil
            var made = RenderedEntry(
                id: entry.hash,
                type: payload.type,
                author: entry.author,
                device: entry.device,
                wallTime: entry.wallTime,
                room: entry.room,
                content: comment.map { .text($0.text) } ?? content(of: payload),
                editedAt: nil,
                replyingTo: comment?.target,
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
            return .shows(made)

        case .edit:
            return (try? payload.decode(EditBody.self)).map(RenderStep.edits) ?? .nothing

        case .tombstone:
            return (try? payload.decode(TombstoneBody.self)).map(RenderStep.withdraws) ?? .nothing

        case .reaction:
            return (try? payload.decode(ReactionBody.self)).map(RenderStep.reacts) ?? .nothing

        default:
            return .shows(
                RenderedEntry(
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
                ))
        }
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
