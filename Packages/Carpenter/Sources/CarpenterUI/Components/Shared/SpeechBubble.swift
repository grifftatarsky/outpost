import SwiftUI

struct MarkBubble: Identifiable {
    let id: String
    let text: Text
    let closable: Bool
    let endsWhenMarkIsTapped: Bool

    static var all: [MarkBubble] {
        [
            MarkBubble(
                id: "tap-me",
                // COPY BEGIN 1cea6f67 [NEEDS HUMAN REVIEW]
                text: Text("tap me!", bundle: .module),
                // COPY END 1cea6f67
                closable: false, endsWhenMarkIsTapped: true)
        ]
    }
}

@MainActor
@Observable
final class MarkBubbles {
    private static let finishedKey = "you.markBubbles.finished"

    private let defaults: UserDefaults
    private(set) var finished: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        finished = Set(defaults.stringArray(forKey: Self.finishedKey) ?? [])
    }

    var current: MarkBubble? {
        MarkBubble.all.first { !finished.contains($0.id) }
    }

    func markTapped() {
        guard let current, current.endsWhenMarkIsTapped else { return }
        finish(current.id)
    }

    func close(_ id: String) {
        finish(id)
    }

    private func finish(_ id: String) {
        finished.insert(id)
        defaults.set(Array(finished).sorted(), forKey: Self.finishedKey)
    }
}

struct SpeechBubble: View {
    @Environment(\.palette) private var palette

    let text: Text
    var onClose: (() -> Void)?

    private static let tail: CGFloat = 8

    var body: some View {
        HStack(spacing: 8) {
            text
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // COPY BEGIN 8b738263 [NEEDS HUMAN REVIEW]
                .accessibilityLabel(Text("Close", bundle: .module))
                // COPY END 8b738263
            }
        }
        .padding(.leading, 12 + Self.tail)
        .padding(.trailing, onClose == nil ? 12 : 8)
        .padding(.vertical, 8)
        .background {
            SpeechBubbleShape(tail: Self.tail)
                .fill(palette.accentFill)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        }
    }
}

struct SpeechBubbleShape: Shape {
    let tail: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height)
        let bubble = Path(roundedRect: body, cornerRadius: min(14, body.height / 2), style: .continuous)
        var point = Path()
        point.move(to: CGPoint(x: body.minX + 6, y: body.maxY - 14))
        point.addQuadCurve(
            to: CGPoint(x: rect.minX, y: body.maxY + 2),
            control: CGPoint(x: body.minX + 2, y: body.maxY - 2))
        point.addQuadCurve(
            to: CGPoint(x: body.minX + 14, y: body.maxY - 2),
            control: CGPoint(x: body.minX + 6, y: body.maxY + 1))
        point.closeSubpath()
        return bubble.union(point)
    }
}
