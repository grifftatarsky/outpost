import Foundation

public struct PreparedMedia: Hashable, Sendable {
    public let kind: MediaKind
    public let width: Int
    public let height: Int
    public let bytes: Data
    public let file: URL?
    public let preview: Data?
    public let caption: String?
    public let duration: TimeInterval?

    public init(
        kind: MediaKind, width: Int, height: Int, bytes: Data = Data(), file: URL? = nil, preview: Data?,
        caption: String? = nil, duration: TimeInterval? = nil
    ) {
        self.kind = kind
        self.width = width
        self.height = height
        self.bytes = bytes
        self.file = file
        self.preview = preview
        self.caption = caption
        self.duration = duration
    }
}

public enum PickedMedia: Sendable {
    case image(Data)
    case video(URL)
    case videoToFit(URL)

    public var clip: URL? {
        switch self {
        case .image: nil
        case .video(let url), .videoToFit(let url): url
        }
    }

    public var isMadeToFit: Bool {
        if case .videoToFit = self { return true }
        return false
    }

    public var madeToFit: PickedMedia {
        if case .video(let url) = self { return .videoToFit(url) }
        return self
    }
}
