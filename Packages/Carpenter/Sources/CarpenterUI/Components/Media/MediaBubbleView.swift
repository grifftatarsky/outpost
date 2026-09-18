import CarpenterKit
import SwiftUI

public struct MediaBubbleView: View {
    @Environment(\.palette) private var palette
    @Environment(\.bubbleMaxWidth) private var bubbleMaxWidth

    private let message: Message
    private let media: MediaAttachment
    private let isMine: Bool
    private let position: BubblePosition
    private let onOpen: (LoadedMedia) -> Void

    static let maximumWidth: CGFloat = 280
    static let maximumHeight: CGFloat = 340
    static let minimumHeight: CGFloat = 90

    public init(
        message: Message, media: MediaAttachment, isMine: Bool, position: BubblePosition,
        onOpen: @escaping (LoadedMedia) -> Void
    ) {
        self.message = message
        self.media = media
        self.isMine = isMine
        self.position = position
        self.onOpen = onOpen
    }

    static func frame(for media: MediaAttachment, maxWidth: CGFloat) -> CGSize {
        let ceiling = min(maxWidth.isFinite ? maxWidth : maximumWidth, maximumWidth)
        let aspect = media.aspectRatio
        var width = ceiling
        var height = width / aspect
        if height > maximumHeight {
            height = maximumHeight
            width = height * aspect
        }
        if height < minimumHeight {
            height = minimumHeight
            width = min(ceiling, height * aspect)
        }
        return CGSize(width: width, height: height)
    }

    public var body: some View {
        let frame = Self.frame(for: media, maxWidth: bubbleMaxWidth)
        let shape = BubbleShape(isMine: isMine, position: position)

        VStack(alignment: .leading, spacing: 0) {
            MediaPictureView(media: media, author: message.author.id, onOpen: onOpen)
                .frame(width: frame.width, height: frame.height)
                .clipped()

            if !message.body.isEmpty {
                Text(verbatim: message.body)
                    .font(CarpenterFont.bubble)
                    .foregroundStyle(isMine ? palette.textOnSentBubble : palette.textOnAccentTint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(width: frame.width, alignment: .leading)
            }
        }
        .background(shape.fill(isMine ? palette.sentBubbleFill : palette.accentTint))
        .clipShape(shape)
    }

    static func length(_ seconds: TimeInterval) -> String { MediaPictureView.length(seconds) }
}

#if DEBUG
    #Preview("A photo bubble, no loader") {
        MediaBubbleView(
            message: Message(
                id: MessageID(entry: EntryHash(rawValue: Data([1]))),
                author: Fixtures.hastur, body: "", sentAt: .now, isMine: false),
            media: MediaAttachment(
                reference: AttachmentReference(
                    id: AttachmentID(), key: Data(repeating: 1, count: 32),
                    digest: Data(repeating: 2, count: 32), byteCount: 100),
                kind: .image, width: 1600, height: 1200, preview: nil),
            isMine: false, position: .only, onOpen: { _ in }
        )
        .padding()
        .themed(.default)
    }
#endif
