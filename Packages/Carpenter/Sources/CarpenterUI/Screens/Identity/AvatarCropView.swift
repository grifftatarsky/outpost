import CarpenterMedia
import CoreGraphics
import SwiftUI

public struct AvatarCropView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let data: Data
    private let onUse: (AvatarCrop) -> Void

    @State private var picture: CGImage?
    @State private var couldNotRead = false

    @State private var zoom: CGFloat = 1
    @State private var pinching: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragging: CGSize = .zero

    private static let deepest: CGFloat = 6

    public init(_ data: Data, onUse: @escaping (AvatarCrop) -> Void) {
        self.data = data
        self.onUse = onUse
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let picture {
                stage(picture)
            } else if couldNotRead {
                ContentUnavailableView {
                    Text("That picture could not be opened", bundle: .module)
                } description: {
                    Text("Try another one.", bundle: .module)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            buttons
        }
        .background(palette.background)
        .task {
            guard let read = try? ImagePreparer.thumbnail(data, edge: 1200) else {
                couldNotRead = true
                return
            }
            picture = read
        }
    }

    private func stage(_ image: CGImage) -> some View {
        GeometryReader { geometry in
            let circle = min(geometry.size.width - 48, geometry.size.height - 48, 320)
            let size = drawn(image, at: zoom * pinching)
            let bounds = room(size)
            let shift = held(
                CGSize(
                    width: offset.width * pinching + dragging.width,
                    height: offset.height * pinching + dragging.height), within: bounds)

            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: size.width * circle, height: size.height * circle)
                    .offset(x: shift.width * circle, y: shift.height * circle)
                window(circle)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(.rect)
            .gesture(
                SimultaneousGesture(
                    DragGesture()
                        .onChanged {
                            dragging = CGSize(
                                width: $0.translation.width / circle,
                                height: $0.translation.height / circle)
                        }
                        .onEnded { _ in
                            offset = CGSize(
                                width: shift.width / pinching, height: shift.height / pinching)
                            dragging = .zero
                        },
                    MagnifyGesture()
                        .onChanged { value in
                            pinching = min(Self.deepest / zoom, max(1 / zoom, value.magnification))
                        }
                        .onEnded { _ in
                            let settled = min(Self.deepest, max(1, zoom * pinching))
                            let landing = held(shift, within: room(drawn(image, at: settled)))

                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                                offset = landing
                                zoom = settled
                                pinching = 1
                            }
                        }
                )
            )
            .onChange(of: circle) { _, _ in
                offset = held(offset, within: room(drawn(image, at: zoom)))
            }
            .accessibilityLabel(Text("Move and scale your picture", bundle: .module))
        }
    }

    private func window(_ circle: CGFloat) -> some View {
        Rectangle()
            .fill(.black.opacity(0.55))
            .overlay {
                Circle()
                    .frame(width: circle, height: circle)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                    .frame(width: circle, height: circle)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Text("Drag to move, pinch to zoom.", bundle: .module)
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 20)

            Button {
                onUse(crop())
                dismiss()
            } label: {
                Text("Use photo", bundle: .module).primaryAction()
            }
            .prominentActionButton()
            .disabled(picture == nil)

            Button {
                dismiss()
            } label: {
                Text("Cancel", bundle: .module)
                    .font(CarpenterFont.button)
                    .foregroundStyle(palette.accentColor)
                    .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: The arithmetic, all of it in circle-diameters

    private func drawn(_ image: CGImage, at scale: CGFloat) -> CGSize {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard width > 0, height > 0 else { return CGSize(width: scale, height: scale) }
        return width >= height
            ? CGSize(width: scale * width / height, height: scale)
            : CGSize(width: scale, height: scale * height / width)
    }

    private func room(_ size: CGSize) -> CGSize {
        CGSize(width: max(0, (size.width - 1) / 2), height: max(0, (size.height - 1) / 2))
    }

    private func held(_ offset: CGSize, within room: CGSize) -> CGSize {
        CGSize(
            width: min(room.width, max(-room.width, offset.width)),
            height: min(room.height, max(-room.height, offset.height)))
    }

    private func crop() -> AvatarCrop {
        guard let picture else { return .whole }
        let size = drawn(picture, at: zoom)
        return AvatarCrop(
            x: Double(0.5 - (offset.width + 0.5) / size.width),
            y: Double(0.5 - (offset.height + 0.5) / size.height),
            width: Double(1 / size.width),
            height: Double(1 / size.height))
    }
}

#if DEBUG
    #Preview("Choosing part of a picture") {
        AvatarCropView(Data()) { _ in }
            .themed(.default)
    }
#endif
