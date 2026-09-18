import CarpenterKit
import SwiftUI

public struct MediaPictureView: View {
    @Environment(\.palette) private var palette
    @Environment(\.mediaLoader) private var loader
    @Environment(\.blursSensitiveMedia) private var blursSensitive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let media: MediaAttachment
    private let author: ParticipantID
    private let onOpen: (LoadedMedia) -> Void

    public init(media: MediaAttachment, author: ParticipantID, onOpen: @escaping (LoadedMedia) -> Void) {
        self.media = media
        self.author = author
        self.onOpen = onOpen
    }

    public var body: some View {
        let state = loader?.state(of: media, sentBy: author) ?? .idle

        picture(state)
            .contentShape(.rect)
            .onTapGesture { act(on: state) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(for: state))
            .accessibilityAddTraits(isActionable(state) ? [.isImage, .isButton] : [.isImage])
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: state)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isRevealed)
    }

    private var isVideo: Bool { media.kind == .video }
    private var isRevealed: Bool { loader?.isRevealed(media.id) ?? false }

    private func isHidden(_ loaded: LoadedMedia) -> Bool {
        loaded.verdict == .sensitive && blursSensitive && !isRevealed
    }

    private func isActionable(_ state: MediaLoadState) -> Bool {
        switch state {
        case .loaded, .failed: true
        case .idle, .loading, .gone: false
        }
    }

    @ViewBuilder
    private func picture(_ state: MediaLoadState) -> some View {
        ZStack {
            placeholder

            switch state {
            case .idle:
                EmptyView()
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .loaded(let loaded):
                if isHidden(loaded) {
                    loaded.image.image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 28)
                    sensitiveNotice
                } else {
                    loaded.image.image
                        .resizable()
                        .scaledToFill()
                    if isVideo { clipMarks }
                }
            case .gone:
                notice(
                    symbol: isVideo ? "video.badge.exclamationmark" : "photo.badge.exclamationmark",
                    title: Text("No longer available", bundle: .module),
                    detail: isVideo
                        ? Text("The sender's iCloud has let this video go.", bundle: .module)
                        : Text("The sender's iCloud has let this photo go.", bundle: .module))
            case .failed:
                notice(
                    symbol: "arrow.clockwise",
                    title: Text("Could not load", bundle: .module),
                    detail: Text("Tap to try again.", bundle: .module))
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if let preview = loader?.preview(of: media) {
            preview.image
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .blur(radius: 12)
        } else {
            Color.clear
        }
    }

    private var clipMarks: some View {
        GlassEffectContainer(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .overMedia(in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let duration = media.duration {
                    Text(Self.length(duration))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overMedia(in: Capsule())
                        .padding(8)
                }
            }
        }
    }

    public static func length(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds.rounded())).formatted(.time(pattern: .minuteSecond))
    }

    private var sensitiveNotice: some View {
        Button {
            loader?.reveal(media.id)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "eye.slash")
                    .font(.title2)
                isVideo
                    ? Text("Sensitive video", bundle: .module)
                        .font(CarpenterFont.footnote.weight(.semibold))
                    : Text("Sensitive photo", bundle: .module)
                        .font(CarpenterFont.footnote.weight(.semibold))
                Text("Tap to show", bundle: .module)
                    .font(CarpenterFont.caption)
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .buttonStyle(.plain)
        .overMedia(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
        .accessibilityLabel(
            isVideo
                ? Text("Sensitive video, hidden. Show it.", bundle: .module)
                : Text("Sensitive photo, hidden. Show it.", bundle: .module))
    }

    private func notice(symbol: String, title: Text, detail: Text) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.title3)
            title
                .font(CarpenterFont.footnote.weight(.semibold))
            detail
                .font(CarpenterFont.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(12)
        .overMedia(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(8)
    }

    private func act(on state: MediaLoadState) {
        switch state {
        case .loaded(let loaded):
            if isHidden(loaded) {
                loader?.reveal(media.id)
            } else {
                onOpen(loaded)
            }
        case .failed:
            loader?.retry(media, sentBy: author)
        case .idle, .loading, .gone:
            break
        }
    }

    private func label(for state: MediaLoadState) -> Text {
        let what = isVideo
            ? Text("Video, \(Self.length(media.duration ?? 0))", bundle: .module)
            : Text("Photo", bundle: .module)
        switch state {
        case .idle, .loading:
            return Text("\(what), loading", bundle: .module)
        case .loaded(let loaded):
            return isHidden(loaded)
                ? Text("\(what), sensitive, hidden. Double-tap to show.", bundle: .module)
                : what
        case .gone:
            return Text("\(what), no longer available", bundle: .module)
        case .failed:
            return Text("\(what), could not load. Double-tap to try again.", bundle: .module)
        }
    }
}

struct PostPicturesView: View {
    @Environment(\.palette) private var palette

    let post: OutpostPost
    let media: [MediaAttachment]

    @State private var viewing: Viewed?
    @State private var reporting: ViewedItem?

    private static let maximumHeight: CGFloat = 420
    private static let rowHeight: CGFloat = 260
    private static let spacing: CGFloat = 3

    private struct Viewed: Identifiable {
        let id = UUID()
        let loaded: LoadedMedia
    }

    var body: some View {
        Group {
            switch media.count {
            case 0:
                EmptyView()
            case 1:
                tile(media[0])
                    .aspectRatio(media[0].aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: Self.maximumHeight, alignment: .leading)
            case 2:
                HStack(spacing: Self.spacing) {
                    tile(media[0])
                    tile(media[1])
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight)
            case 3:
                HStack(spacing: Self.spacing) {
                    tile(media[0])
                    VStack(spacing: Self.spacing) {
                        tile(media[1])
                        tile(media[2])
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight)
            default:
                VStack(spacing: Self.spacing) {
                    HStack(spacing: Self.spacing) {
                        tile(media[0])
                        tile(media[1])
                    }
                    HStack(spacing: Self.spacing) {
                        tile(media[2])
                        tile(media[3])
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .presentingPostViewer($viewing) { viewed in
            MediaViewerView(
                loaded: viewed.loaded, item: ViewedItem(post),
                onReport: { reporting = ViewedItem(post) })
        }
        .sheet(item: $reporting) { item in
            ReportView(item: item)
        }
    }

    private func tile(_ one: MediaAttachment) -> some View {
        Color.clear
            .overlay {
                MediaPictureView(media: one, author: post.author.id) { viewing = Viewed(loaded: $0) }
            }
            .background(palette.neutralFill)
            .clipped()
            .contentShape(.rect)
    }
}

extension View {
    fileprivate func presentingPostViewer<Item: Identifiable>(
        _ item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> some View
    ) -> some View {
        #if os(iOS)
            fullScreenCover(item: item, content: content)
        #else
            sheet(item: item, content: content)
        #endif
    }
}

extension View {
    fileprivate func overMedia(in shape: some Shape, interactive: Bool = false) -> some View {
        glassEffect(interactive ? .clear.interactive() : .clear, in: shape)
            .background(.black.opacity(CarpenterMetrics.mediaOverlayDimming), in: shape)
    }
}
