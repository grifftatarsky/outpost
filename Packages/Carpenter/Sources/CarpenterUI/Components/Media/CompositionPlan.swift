import CarpenterKit
import Foundation

public struct StagedAttachment: Identifiable, Sendable {
    public let id: UUID
    public var picked: PickedMedia
    public let kind: MediaKind
    public let thumbnail: DecodedImage?
    public var duration: TimeInterval?

    public init(
        id: UUID = UUID(), picked: PickedMedia, kind: MediaKind, thumbnail: DecodedImage?,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.picked = picked
        self.kind = kind
        self.thumbnail = thumbnail
        self.duration = duration
    }

    public func needsTrim(limit: TimeInterval) -> Bool {
        kind == .video && (duration ?? 0) > limit
    }
}

public enum CompositionStep: Equatable, Sendable {
    case media(index: Int, caption: String?)
    case text(String)
}

public enum CompositionPlan {
    public static func steps(text: String, itemCount: Int) -> [CompositionStep] {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch itemCount {
        case 0:
            return words.isEmpty ? [] : [.text(words)]
        case 1:
            return [.media(index: 0, caption: words.isEmpty ? nil : words)]
        default:
            var steps = (0..<itemCount).map { CompositionStep.media(index: $0, caption: nil) }
            if !words.isEmpty { steps.append(.text(words)) }
            return steps
        }
    }
}
