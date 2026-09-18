import Foundation

public struct PreparedMedia: Hashable, Sendable {
    public let kind: MediaKind
    public let width: Int
    public let height: Int
    public let bytes: Data
    public let preview: Data?
    public let caption: String?
    public let duration: TimeInterval?

    public init(
        kind: MediaKind, width: Int, height: Int, bytes: Data, preview: Data?,
        caption: String? = nil, duration: TimeInterval? = nil
    ) {
        self.kind = kind
        self.width = width
        self.height = height
        self.bytes = bytes
        self.preview = preview
        self.caption = caption
        self.duration = duration
    }
}

public enum PickedMedia: Sendable {
    case image(Data)
    case video(URL)
}
