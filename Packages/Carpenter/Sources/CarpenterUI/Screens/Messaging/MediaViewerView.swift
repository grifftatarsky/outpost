import AVKit
import CarpenterKit
import SwiftUI

public struct MediaViewerView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let loaded: LoadedMedia
    private let item: ViewedItem
    private let onReport: (() -> Void)?

    @State private var scale: CGFloat = 1
    @State private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var drag: CGSize = .zero
    @State private var player: AVPlayer?

    private static let minimumScale: CGFloat = 1
    private static let maximumScale: CGFloat = 4
    private static let doubleTapScale: CGFloat = 2.5

    public init(loaded: LoadedMedia, item: ViewedItem, onReport: (() -> Void)?) {
        self.loaded = loaded
        self.item = item
        self.onReport = onReport
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let video = loaded.video {
                    clip(video)
                } else {
                    photo
                }
            }
            .toolbar {
                // COPY BEGIN ca6cec86 [NEEDS HUMAN REVIEW]
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close", bundle: .module))
                        .barIconLargeContent(Text("Close", bundle: .module), systemImage: "xmark")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    share
                    if let onReport, !item.isMine {
                        Button {
                            dismiss()
                            onReport()
                        } label: {
                            Image(systemName: "flag")
                        }
                        .accessibilityLabel(
                            loaded.video == nil
                                ? Text("Report this photo", bundle: .module)
                                : Text("Report this video", bundle: .module))
                    }
                // COPY END ca6cec86
                }
            }
        }
    }

    private var photo: some View {
        GeometryReader { frame in
            loaded.image.image
                .resizable()
                .scaledToFit()
                .frame(width: frame.size.width, height: frame.size.height)
                .scaleEffect(scale * pinch)
                .offset(held(offset + drag, at: scale * pinch, in: frame.size))
                .gesture(
                    MagnifyGesture()
                        .onChanged { pinch = $0.magnification }
                        .onEnded { value in
                            scale = min(
                                max(scale * value.magnification, Self.minimumScale),
                                Self.maximumScale)
                            pinch = 1
                            offset = held(offset, at: scale, in: frame.size)
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { if scale > Self.minimumScale { drag = $0.translation } }
                        .onEnded { _ in
                            offset = held(offset + drag, at: scale, in: frame.size)
                            drag = .zero
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                        scale = scale > Self.minimumScale ? Self.minimumScale : Self.doubleTapScale
                        offset = .zero
                        drag = .zero
                    }
                }
                // COPY BEGIN 429482dd [NEEDS HUMAN REVIEW]
                .accessibilityLabel(Text("Photo", bundle: .module))
                // COPY END 429482dd
                .accessibilityZoomAction { action in
                    switch action.direction {
                    case .zoomIn: scale = min(scale * 1.5, Self.maximumScale)
                    case .zoomOut:
                        scale = max(scale / 1.5, Self.minimumScale)
                        offset = held(offset, at: scale, in: frame.size)
                    @unknown default: break
                    }
                }
        }
    }

    private func held(_ wanted: CGSize, at scale: CGFloat, in frame: CGSize) -> CGSize {
        guard scale > 1 else { return .zero }
        let slack = CGSize(
            width: frame.width * (scale - 1) / 2, height: frame.height * (scale - 1) / 2)
        return CGSize(
            width: min(max(wanted.width, -slack.width), slack.width),
            height: min(max(wanted.height, -slack.height), slack.height))
    }

    // COPY BEGIN cf4bf019 [NEEDS HUMAN REVIEW]
    private func clip(_ url: URL) -> some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                let made = AVPlayer(url: url)
                player = made
                made.play()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
            .accessibilityLabel(Text("Video", bundle: .module))
    }
    // COPY END cf4bf019

    // COPY BEGIN ea0585b6 [NEEDS HUMAN REVIEW]
    @ViewBuilder
    private var share: some View {
        if let video = loaded.video {
            ShareLink(
                item: video,
                preview: SharePreview(Text("Video", bundle: .module), image: loaded.image.image)
            ) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel(Text("Share or save", bundle: .module))
        } else {
            ShareLink(
                item: loaded.image.image,
                preview: SharePreview(Text("Photo", bundle: .module), image: loaded.image.image)
            ) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel(Text("Share or save", bundle: .module))
        }
    }
    // COPY END ea0585b6
}

private func + (left: CGSize, right: CGSize) -> CGSize {
    CGSize(width: left.width + right.width, height: left.height + right.height)
}
