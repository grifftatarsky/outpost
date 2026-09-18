import Foundation

public struct Projection: Sendable {
    let viewer: ParticipantID
    let rendered: [RenderedEntry]

    public init(
        viewer: ParticipantID, rendered: [RenderedEntry], revealsNames: Bool = true,
        viewerName: String? = nil, nicknames: [ParticipantID: String] = [:],
        met: Set<ParticipantID>? = nil, anonPersona: AnonPersona = .default
    ) {
        self.viewer = viewer
        self.rendered = rendered
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

    static func isWithdrawn(_ entry: RenderedEntry) -> Bool {
        if case .withdrawn = entry.content { return true }
        return false
    }

    static let withdrawnMessage = String(
        localized: "This message was withdrawn.", bundle: .module,
        comment: "Placeholder for a withdrawn message")
    static let withdrawnPost = String(
        localized: "This post was withdrawn.", bundle: .module,
        comment: "Placeholder for a withdrawn post")
    static let withdrawnComment = String(
        localized: "This comment was withdrawn.", bundle: .module,
        comment: "Placeholder for a withdrawn comment")

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
            return String(
                localized: "Not readable on this device.", bundle: .module,
                comment: "Placeholder for an entry whose key this device does not hold")
        case .unrenderable(_, let fallback):
            return fallback
                ?? String(
                    localized: "Not supported by this version.", bundle: .module,
                    comment: "Placeholder for an unknown payload type with no fallback")
        }
    }
}
