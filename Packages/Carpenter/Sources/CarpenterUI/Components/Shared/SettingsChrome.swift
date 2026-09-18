import SwiftUI

public struct IconTile<Glyph: View>: View {
    private let fill: Color
    private let size: CGFloat
    private let glyph: Glyph

    public init(fill: Color, size: CGFloat = 29, @ViewBuilder glyph: () -> Glyph) {
        self.fill = fill
        self.size = size
        self.glyph = glyph()
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                glyph
                    .foregroundStyle(.white)
                    .font(.system(size: size * 0.55, weight: .medium))
            }
            .accessibilityHidden(true)
    }
}

extension IconTile where Glyph == Image {
    public init(_ symbol: String, fill: Color, size: CGFloat = 29) {
        self.init(fill: fill, size: size) { Image(systemName: symbol) }
    }
}

public enum TileTone: Sendable {
    case feature
    case device
    case destructive
}

extension Palette {
    public func tileFill(_ tone: TileTone) -> Color {
        switch tone {
        case .feature: accentFill
        case .device: Color.gray
        case .destructive: destructiveFill
        }
    }
}

struct SettingsRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    let icon: String
    var tone: TileTone = .feature
    let title: Text
    var subtitle: Text?
    var detail: Text?
    var swatch = false

    var body: some View {
        let layout = AnyLayout(
            typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        )

        return layout {
            IconTile(icon, fill: palette.tileFill(tone))

            VStack(alignment: .leading, spacing: 2) {
                title
                    .foregroundStyle(palette.primaryText)
                if let subtitle {
                    subtitle
                        .font(CarpenterFont.caption)
                        .foregroundStyle(palette.tertiaryText)
                }
            }

            Spacer(minLength: 8)

            if swatch {
                Circle().fill(palette.accentColor).frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }

            if let detail {
                detail
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            }
        }
    }
}

struct SettingsToggle: View {
    @Environment(\.palette) private var palette

    let icon: String
    var tone: TileTone = .feature
    let title: Text
    var detail: Text?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRow(icon: icon, tone: tone, title: title, detail: detail)
        }
        .toggleStyle(.switch)
        .tint(palette.accentColor)
    }
}

struct SettingsHeaderCard: View {
    @Environment(\.palette) private var palette

    let icon: String
    var tone: TileTone = .feature
    let title: Text
    let paragraph: Text

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                IconTile(icon, fill: palette.tileFill(tone), size: 56)
                title
                    .font(.title2.weight(.bold))
                    .foregroundStyle(palette.primaryText)
                    .heading()
                paragraph
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        }
        .groupedRowSurface()
    }
}
