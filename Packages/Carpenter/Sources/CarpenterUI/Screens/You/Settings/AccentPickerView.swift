import CarpenterKit
import SwiftUI

public struct AccentPickerView: View {
    @Environment(\.palette) private var palette

    @Binding private var accent: Accent

    public init(accent: Binding<Accent>) {
        _accent = accent
    }

    public var body: some View {
        // COPY BEGIN a6fef78e [NEEDS HUMAN REVIEW]
        ScrollView {
            VStack(spacing: 0) {
                livePreview
                scopeNote
                swatches
                appearanceComparison
            }
            .padding(.top, 20)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(palette.background)
        .navigationTitle(Text("Color", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        // COPY END a6fef78e
    }

    private var livePreview: some View {
        VStack(spacing: 14) {
            // COPY BEGIN d5a308c7 [NEEDS HUMAN REVIEW]
            MessageBubbleView(
                text: String(localized: "is the Goodyear one a blimp or a zeppelin", bundle: .module),
                isMine: false,
                position: .last
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            // COPY END d5a308c7

            // COPY BEGIN 0b71a495 [NEEDS HUMAN REVIEW]
            MessageBubbleView(
                text: String(localized: "it has a frame now, so: neither, and both", bundle: .module),
                isMine: true,
                position: .last
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            // COPY END 0b71a495
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .background(
            palette.elevatedSurface, in: .rect(cornerRadius: CarpenterMetrics.cardRadius, style: .continuous)
        )
        .padding(.horizontal, 16)
    }

    // COPY BEGIN 1ed2b15e [NEEDS HUMAN REVIEW]
    private var scopeNote: some View {
        Text(
            "Applies to every room and your Outpost. Color is a local preference — nobody else sees your choice.",
            bundle: .module
        )
        .font(CarpenterFont.footnote)
        .foregroundStyle(palette.tertiaryText)
        .padding(.horizontal, 34)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }
    // COPY END 1ed2b15e

    private var swatches: some View {
        VStack(spacing: 16) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: CarpenterMetrics.hitTarget), spacing: 12)],
                spacing: 14
            ) {
                ForEach(Accent.allCases, id: \.self) { candidate in
                    Button {
                        // cross-fade only
                        withAnimation(.snappy(duration: 0.2)) { accent = candidate }
                    } label: {
                        AccentSwatchTile(accent: candidate, isSelected: candidate == accent)
                    }
                    .buttonStyle(.plain)
                    .tappable()
                    .accessibilityLabel(candidate.displayName)
                    .accessibilityAddTraits(candidate == accent ? [.isSelected] : [])
                }
            }

            Text(accent.displayName)
                .font(CarpenterFont.navigationTitle)
                .foregroundStyle(palette.primaryText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(
            palette.elevatedSurface, in: .rect(cornerRadius: CarpenterMetrics.cardRadius, style: .continuous)
        )
        .padding(.horizontal, 16)
    }

    private var appearanceComparison: some View {
        HStack(spacing: 12) {
            AppearanceSample(accent: accent, appearance: .dark)
            AppearanceSample(accent: accent, appearance: .light)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 34)
    }
}

private struct AccentSwatchTile: View {
    @Environment(\.palette) private var palette

    let accent: Accent
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(Color(rgb: accent.tone(for: palette.appearance).rgb))
            .frame(width: 40, height: 40)
            .overlay {
                Circle()
                    .strokeBorder(
                        isSelected ? Color(rgb: accent.tone(for: palette.appearance).rgb) : .clear,
                        lineWidth: 2.5
                    )
                    .padding(-5.5)
            }
    }
}

private struct AppearanceSample: View {
    let accent: Accent
    let appearance: Appearance

    private var sample: Palette { Palette(accent: accent, appearance: appearance) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // COPY BEGIN dd25d18a [NEEDS HUMAN REVIEW]
            Text(appearance == .dark ? "Dark" : "Light", bundle: .module)
                .sectionHeading()
                .kerning(0.55)
                .textCase(.uppercase)
                .foregroundStyle(sample.tertiaryText)
            // COPY END dd25d18a

            // COPY BEGIN cc99c8b7 [NEEDS HUMAN REVIEW]
            bubble("hydrogen, obviously", isMine: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            bubble("helium coward", isMine: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
            // COPY END cc99c8b7
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            appearance == .dark ? Color(rgb: 0x1C1C_1E) : Color(rgb: 0xF2F2_F7),
            in: .rect(cornerRadius: 18, style: .continuous)
        )
    }

    private func bubble(_ text: String.LocalizationValue, isMine: Bool) -> some View {
        Text(String(localized: text, bundle: .module))
            .font(.footnote)
            .foregroundStyle(isMine ? sample.textOnAccent : sample.textOnAccentTint)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                isMine ? sample.accentColor : sample.accentTint,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 14,
                    bottomLeadingRadius: isMine ? 14 : 5,
                    bottomTrailingRadius: isMine ? 5 : 14,
                    topTrailingRadius: 14,
                    style: .continuous
                )
            )
    }
}

#if DEBUG
    private struct AccentPickerPreview: View {
        @State private var accent = Accent.cobalt

        var body: some View {
            NavigationStack {
                AccentPickerView(accent: $accent)
            }
            .themed(accent)
        }
    }

    #Preview("05 Color — dark") {
        AccentPickerPreview().preferredColorScheme(.dark)
    }

    #Preview("05 Color — light") {
        AccentPickerPreview().preferredColorScheme(.light)
    }
#endif
