import CarpenterKit
import SwiftUI

public struct AnimatedMark: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat
    private let tint: Color?

    @State private var frame = 0
    @State private var direction = 1
    @State private var running = false
    @State private var wantsShut = false
    @State private var landings = 0

    public static let touchInset: CGFloat = 8

    public init(size: CGFloat = 32, tint: Color? = nil) {
        self.size = size
        self.tint = tint
    }

    private static let frameDuration = Duration.milliseconds(200)
    private static let last = MarkFrames.frames.count - 1

    private static func landingFrame(_ direction: Int) -> Int {
        direction == 1 ? MarkFrames.shutFrame - 1 : 0
    }

    public var body: some View {
        Button {
            wantsShut.toggle()
            Task { await settle() }
        } label: {
            MarkFrameView(layers: MarkFrames.frames[frame], color: tint ?? palette.accentColor)
                .frame(width: size, height: size)
                .padding(Self.touchInset)
                .contentShape(.rect)
                .keyframeAnimator(
                    initialValue: CGSize(width: 1, height: 1),
                    trigger: landings
                ) { view, scale in
                    view.scaleEffect(scale, anchor: .bottom)
                } keyframes: { _ in
                    KeyframeTrack(\.width) {
                        CubicKeyframe(1.075, duration: 0.11)
                        CubicKeyframe(0.975, duration: 0.10)
                        CubicKeyframe(1.0, duration: 0.11)
                    }
                    KeyframeTrack(\.height) {
                        CubicKeyframe(0.9, duration: 0.11)
                        CubicKeyframe(1.035, duration: 0.10)
                        CubicKeyframe(1.0, duration: 0.11)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: Branding.displayName))
        .accessibilityAddTraits(.isImage)
        .accessibilityRemoveTraits(.isButton)
    }

    @MainActor
    private func settle() async {
        guard !running else { return }
        guard (frame == Self.last) != wantsShut else { return }

        if reduceMotion {
            frame = wantsShut ? Self.last : 0
            return
        }

        running = true
        direction = wantsShut ? 1 : -1
        let end = wantsShut ? Self.last : 0

        while frame != end {
            try? await Task.sleep(for: Self.frameDuration)
            if Task.isCancelled { break }
            frame += direction
            if frame == Self.landingFrame(direction) { landings += 1 }
        }

        running = false
        await settle()
    }
}

private struct MarkFrameView: View {
    let layers: [MarkFrames.Layer]
    let color: Color

    var body: some View {
        Canvas { context, size in
            context.drawLayer { inner in
                let rect = CGRect(origin: .zero, size: size)
                for layer in layers {
                    let path = MarkPath.path(layer.path, fitting: rect)
                    if layer.punches {
                        inner.blendMode = .destinationOut
                        inner.fill(path, with: .color(.black))
                        inner.blendMode = .normal
                    } else {
                        inner.fill(path, with: .color(color))
                    }
                }
            }
        }
    }
}

enum MarkPath {
    static func path(_ data: String, fitting rect: CGRect) -> Path {
        let box = MarkFrames.viewBox
        let scale = min(rect.width / box.width, rect.height / box.height)
        let dx = rect.midX - box.midX * scale
        let dy = rect.midY - box.midY * scale

        var path = Path()
        let tokens = data.split(separator: " ")
        var index = 0

        func point() -> CGPoint {
            defer { index += 2 }
            guard index + 1 < tokens.count else { return .zero }
            let x = Double(tokens[index]) ?? 0
            let y = Double(tokens[index + 1]) ?? 0
            return CGPoint(x: dx + x * scale, y: dy + y * scale)
        }

        while index < tokens.count {
            let command = tokens[index]
            index += 1
            switch command {
            case "M": path.move(to: point())
            case "L": path.addLine(to: point())
            case "C":
                let control1 = point()
                let control2 = point()
                path.addCurve(to: point(), control1: control1, control2: control2)
            case "Z": path.closeSubpath()
            default: break
            }
        }
        return path
    }
}

#Preview("Animated mark") {
    VStack(spacing: 40) {
        AnimatedMark(size: 120)
        HStack(spacing: 24) {
            AnimatedMark(size: 44)
            AnimatedMark(size: 32)
            AnimatedMark(size: 24)
        }
    }
    .padding(40)
    .environment(\.palette, Palette(accent: .default, appearance: .dark))
}
