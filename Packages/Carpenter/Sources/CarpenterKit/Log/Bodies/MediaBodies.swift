import Foundation

// MARK: Photos and clips, and what a caption says about them

public enum MediaKind: String, Hashable, Sendable, Codable {
    case image
    case video
}

struct Tolerated<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: any Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

public struct MediaBody: Hashable, Sendable, Codable {
    public static let previewByteCap = 6 * 1024

    public let attachment: AttachmentReference
    public let kind: MediaKind
    public let width: Int
    public let height: Int
    public let preview: Data?
    public let caption: String?
    public let duration: TimeInterval?

    public let extras: [MediaBody]

    public init(
        attachment: AttachmentReference,
        kind: MediaKind,
        width: Int,
        height: Int,
        preview: Data?,
        caption: String?,
        duration: TimeInterval? = nil,
        extras: [MediaBody] = []
    ) {
        self.attachment = attachment
        self.kind = kind
        self.width = width
        self.height = height
        self.preview = preview
        self.caption = caption
        self.duration = duration
        self.extras = extras
    }

    private enum CodingKeys: String, CodingKey {
        case attachment, kind, width, height, preview, caption, duration, extras
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attachment = try container.decode(AttachmentReference.self, forKey: .attachment)
        kind = try container.decode(MediaKind.self, forKey: .kind)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        preview = try container.decodeIfPresent(Data.self, forKey: .preview)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        if var list = try? container.nestedUnkeyedContainer(forKey: .extras) {
            var read: [MediaBody] = []
            while !list.isAtEnd {
                if let one = try list.decode(Tolerated<MediaBody>.self).value { read.append(one) }
            }
            extras = read
        } else {
            extras = []
        }
    }

    var alone: MediaBody {
        MediaBody(
            attachment: attachment, kind: kind, width: width, height: height, preview: preview,
            caption: nil, duration: duration)
    }

    public var all: [MediaBody] { [alone] + extras.map(\.alone) }

    public var line: String {
        if let caption, !caption.isEmpty { return "📷 \(caption)" }
        return Self.line(for: kind)
    }

    public static let galleryLimit = 4

    public static func line(for kind: MediaKind) -> String {
        switch kind {
        case .image:
            String(localized: "📷 Photo", bundle: .module, comment: "Stands in for a photo where only text fits")
        case .video:
            String(localized: "🎬 Video", bundle: .module, comment: "Stands in for a video where only text fits")
        }
    }
}
