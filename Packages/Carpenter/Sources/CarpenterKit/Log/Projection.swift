import Foundation

public struct Projection: Sendable {
    let viewer: ParticipantID
    let rendered: [RenderedEntry]
    let roomPositions: [RoomID: [Int]]
    let positionByID: [EntryHash: Int]
    let lastProfiles: [RoomID: RenderedEntry]
    let roomKinds: [RoomID: RoomKind]
    let namedRooms: Set<RoomID>
    let outpostAuthorOrder: [ParticipantID]
    let forked: [FeedKey: Set<UInt64>]
    public let members: [ParticipantID: Member]
    public let supporterBadges: Set<ParticipantID>

    public init(
        viewer: ParticipantID, rendered: [RenderedEntry], revealsNames: Bool = true,
        viewerName: String? = nil, nicknames: [ParticipantID: String] = [:],
        met: Set<ParticipantID>? = nil, anonPersona: AnonPersona = .default
    ) {
        self.viewer = viewer
        self.rendered = rendered
        var roomPositions: [RoomID: [Int]] = [:]
        var positionByID: [EntryHash: Int] = [:]
        var profiles: [RoomID: RenderedEntry] = [:]
        var kinds: [RoomID: RoomKind] = [:]
        var lastPosted: [ParticipantID: Int] = [:]
        var taken: [FeedKey: [UInt64: EntryHash]] = [:]
        var forked: [FeedKey: Set<UInt64>] = [:]
        for (position, entry) in rendered.enumerated() {
            positionByID[entry.id] = position
            if entry.seq > 0 {
                if let first = taken[entry.feedKey]?[entry.seq], first != entry.id {
                    forked[entry.feedKey, default: []].insert(entry.seq)
                } else {
                    taken[entry.feedKey, default: [:]][entry.seq] = entry.id
                }
            }
            if let room = entry.room {
                roomPositions[room, default: []].append(position)
                if entry.type == .roomProfile {
                    profiles[room] = entry
                    if kinds[room] == nil { kinds[room] = entry.roomKind ?? .room }
                }
            } else if entry.isConversation && entry.isReadable {
                lastPosted[entry.author] = position
            }
        }
        self.roomPositions = roomPositions
        self.positionByID = positionByID
        self.forked = forked
        lastProfiles = profiles
        roomKinds = kinds
        namedRooms = Set(profiles.compactMap { room, profile in
            if case .text = profile.content { room } else { nil }
        })
        outpostAuthorOrder = lastPosted.sorted { $0.value > $1.value }.map(\.key)
        (members, supporterBadges) = Self.namesAndBadges(in: rendered)
        self.revealsNames = revealsNames
        self.viewerName = viewerName
        self.nicknames = nicknames
        self.anonPersona = anonPersona
        if let met { onlyName(met) } else { self.met = nil }
    }

    public mutating func onlyName(_ people: Set<ParticipantID>) {
        met = people.union(nicknames.keys)
    }

    public private(set) var met: Set<ParticipantID>?

    public var anonPersona: AnonPersona = .default

    public var viewerName: String?

    public var revealsNames: Bool

    public var nicknames: [ParticipantID: String]

    func entries(in room: RoomID) -> LazyMapSequence<[Int], RenderedEntry> {
        (roomPositions[room] ?? []).lazy.map { rendered[$0] }
    }

    func positioned(in room: RoomID) -> LazyMapSequence<[Int], (position: Int, entry: RenderedEntry)> {
        (roomPositions[room] ?? []).lazy.map { (position: $0, entry: rendered[$0]) }
    }

    static func isWithdrawn(_ entry: RenderedEntry) -> Bool {
        if case .withdrawn = entry.content { return true }
        return false
    }

    // COPY BEGIN 7e088dc8 [NEEDS HUMAN REVIEW]
    static let withdrawnMessage = String(
        localized: "This message was withdrawn.", bundle: .module,
        comment: "Placeholder for a withdrawn message")
    static let withdrawnPost = String(
        localized: "This post was withdrawn.", bundle: .module,
        comment: "Placeholder for a withdrawn post")
    static let withdrawnComment = String(
        localized: "This comment was withdrawn.", bundle: .module,
        comment: "Placeholder for a withdrawn comment")
    // COPY END 7e088dc8

    func preview(
        _ entry: RenderedEntry, withdrawn: String = Projection.withdrawnMessage
    ) -> String {
        switch entry.content {
        case .text(let text):
            return text
        case .media(let body):
            return body.line
        case .withdrawn:
            return withdrawn
        case .sealed:
            // COPY BEGIN 80dfd221 [NEEDS HUMAN REVIEW]
            return String(
                localized: "Not readable on this device.", bundle: .module,
                comment: "Placeholder for an entry whose key this device does not hold")
        case .unrenderable(_, let fallback):
            return fallback
                ?? String(
                    localized: "Not supported by this version.", bundle: .module,
                    comment: "Placeholder for an unknown payload type with no fallback")
            // COPY END 80dfd221
        }
    }
}
