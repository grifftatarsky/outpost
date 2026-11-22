import Foundation

public struct PreparedMedia: Hashable, Sendable {
    public let kind: MediaKind
    public let width: Int
    public let height: Int
    public let bytes: Data
    public let scratch: ScratchFile?
    public let preview: Data?
    public let caption: String?
    public let duration: TimeInterval?

    public init(
        kind: MediaKind, width: Int, height: Int, bytes: Data = Data(), file: ScratchFile? = nil, preview: Data?,
        caption: String? = nil, duration: TimeInterval? = nil
    ) {
        self.kind = kind
        self.width = width
        self.height = height
        self.bytes = bytes
        self.scratch = file
        self.preview = preview
        self.caption = caption
        self.duration = duration
    }

    public var file: URL? { scratch?.url }

    public func discardFile() {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file)
    }
}

public enum PickedMedia: Sendable {
    case image(Data)
    case video(ScratchFile)
    case videoToFit(ScratchFile)

    public var isMadeToFit: Bool {
        if case .videoToFit = self { return true }
        return false
    }

    public var madeToFit: PickedMedia {
        if case .video(let file) = self { return .videoToFit(file) }
        return self
    }
}
