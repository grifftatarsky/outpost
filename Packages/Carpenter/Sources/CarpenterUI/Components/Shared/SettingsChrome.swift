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

struct SettingsPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        #if os(macOS)
            Form { content }
                .formStyle(.grouped)
                .buttonStyle(FormRowButtonStyle())
        #else
            List { content }
        #endif
    }
}

#if os(macOS)
    private struct FormRowButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(.tint)
                .opacity(configuration.isPressed ? 0.55 : 1)
                .contentShape(.rect)
        }
    }
#endif

private struct PageBackground: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        #if os(macOS)
            content
        #else
            content.background(palette.background)
        #endif
    }
}

extension View {
    func pageBackground() -> some View {
        modifier(PageBackground())
    }

    @ViewBuilder
    func listSurfaceHidden() -> some View {
        #if os(macOS)
            self
        #else
            scrollContentBackground(.hidden)
        #endif
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
        #if os(macOS)
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    if let subtitle {
                        subtitle
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if swatch {
                    Circle().fill(palette.accentColor).frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
                if let detail {
                    detail
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(.rect)
        #else
            phoneRow
        #endif
    }

    private var phoneRow: some View {
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
            #if os(macOS)
                title
                if let detail { detail }
            #else
                SettingsRow(icon: icon, tone: tone, title: title, detail: detail)
            #endif
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
        #if os(macOS)
            Section {
                HStack(alignment: .top, spacing: 12) {
                    IconTile(icon, fill: palette.tileFill(tone), size: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        title
                            .font(.headline)
                            .heading()
                        paragraph
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
        #else
            phoneCard
        #endif
    }

    private var phoneCard: some View {
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
