import CarpenterKit
import SwiftUI

extension Color {
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: opacity
        )
    }
}

public struct Palette: Equatable, Sendable {
    public let accent: Accent
    public let appearance: Appearance

    public let contrast: ColorSchemeContrast

    public init(
        accent: Accent, appearance: Appearance, contrast: ColorSchemeContrast = .standard
    ) {
        self.accent = accent
        self.appearance = appearance
        self.contrast = contrast
    }

    public static func adjusted(
        _ opacity: Double, for contrast: ColorSchemeContrast
    ) -> Double {
        guard contrast == .increased else { return opacity }
        return min(1, opacity + (1 - opacity) * 0.5)
    }

    private func adjusted(_ opacity: Double) -> Double {
        Self.adjusted(opacity, for: contrast)
    }

    static let increasedFillStep = 0.08

    private func adjustedFill(_ opacity: Double) -> Double {
        contrast == .increased ? min(1, opacity + Self.increasedFillStep) : opacity
    }

    private var tone: AccentTone { accent.tone(for: appearance) }
    private var isDark: Bool { appearance == .dark }

    // MARK: Accent

    public var accentColor: Color { accentSwatch.color }
    public var accentSwatch: Swatch { Swatch(tone.rgb) }

    public var accentTint: Color { accentTintSwatch.color }
    public var accentTintSwatch: Swatch { Swatch(tone.rgb, opacity: tone.tintOpacity) }

    public var textOnAccentTint: Color { textOnAccentTintSwatch.color }
    public var textOnAccentTintSwatch: Swatch { isDark ? Swatch(0xFFFF_FF) : Swatch(0x0000_00) }

    public var textOnAccent: Color { textOnAccentSwatch.color }
    public var textOnAccentSwatch: Swatch {
        let white = Swatch(0xFFFF_FF)
        let black = Swatch(0x0000_00)
        return WCAG.contrastRatio(white, accentSwatch) >= WCAG.contrastRatio(black, accentSwatch)
            ? white : black
    }

    public var accentFillSwatch: Swatch {
        Self.fill(carryingWhiteOver: accentSwatch)
    }

    public var accentFill: Color { accentFillSwatch.color }

    static func fill(carryingWhiteOver base: Swatch) -> Swatch {
        var swatch = base
        var step = 0.0
        while WCAG.contrastRatio(Swatch(0xFFFF_FF), swatch) < Self.fillTarget, step < 0.9 {
            step += 0.05
            swatch = base.darkened(by: step)
        }
        return swatch
    }

    static let fillTarget = 4.6

    public var sentBubbleSwatch: Swatch { accentFillSwatch }

    public var sentBubbleFill: Color { sentBubbleSwatch.color }

    public var textOnSentBubble: Color { .white }

    public var secondaryActionLabel: Color { secondaryActionLabelSwatch.color }
    public var secondaryActionLabelSwatch: Swatch {
        var label = accentSwatch
        var step = 0.0
        while !Self.secondaryActionReads(label, accent: accentSwatch, grounds: secondaryActionGrounds),
            step < 0.96
        {
            step += 0.02
            label = isDark ? accentSwatch.lightened(by: step) : accentSwatch.darkened(by: step)
        }
        return label
    }

    static let secondaryActionTintRange: [Double] = [0.10, 0.14, 0.18, 0.22, 0.28]
    static let secondaryActionTarget = 4.8

    var secondaryActionGrounds: [Swatch] { [backgroundSwatch, contentSurfaceSwatch] }

    static func secondaryActionReads(_ label: Swatch, accent: Swatch, grounds: [Swatch]) -> Bool {
        grounds.allSatisfy { ground in
            secondaryActionTintRange.allSatisfy { opacity in
                let capsule = Swatch(accent.rgb, opacity: opacity).over(ground)
                return WCAG.contrastRatio(label, capsule) >= secondaryActionTarget
            }
        }
    }

    public var destructiveFillSwatch: Swatch {
        Self.fill(carryingWhiteOver: Swatch(0xD138_2F))
    }

    public var destructiveFill: Color { destructiveFillSwatch.color }

    public var destructiveSwatch: Swatch {
        Self.label(
            from: isDark ? Swatch(0xFF42_45) : Swatch(0xD138_2F), readingOn: labelGrounds,
            lightening: isDark)
    }
    public var destructive: Color { destructiveSwatch.color }

    public var destructiveActionLabel: Color { destructiveActionLabelSwatch.color }
    public var destructiveActionLabelSwatch: Swatch {
        let base = destructiveSwatch
        var label = base
        var step = 0.0
        while !Self.secondaryActionReads(label, accent: base, grounds: secondaryActionGrounds),
            step < 0.96
        {
            step += 0.02
            label = isDark ? base.lightened(by: step) : base.darkened(by: step)
        }
        return label
    }

    var labelGrounds: [Swatch] {
        [backgroundSwatch, contentSurfaceSwatch, elevatedSurfaceSwatch].flatMap { ground in
            [ground, fieldFillSwatch.over(ground)]
        }
    }

    static func label(from base: Swatch, readingOn grounds: [Swatch], lightening: Bool) -> Swatch {
        var label = base
        var step = 0.0
        while grounds.contains(where: { WCAG.contrastRatio(label, $0) < WCAG.Requirement.normalText.ratio }),
            step < 0.96
        {
            step += 0.02
            label = lightening ? base.lightened(by: step) : base.darkened(by: step)
        }
        return label
    }

    public var unlitMarkSwatch: Swatch {
        var opacity = Self.unlitMarkOpacity
        func reads(_ ground: Swatch) -> Bool {
            WCAG.contrastRatio(Swatch(accentSwatch.rgb, opacity: opacity).over(ground), ground)
                >= WCAG.Requirement.userInterface.ratio
        }
        while ![backgroundSwatch, contentSurfaceSwatch, elevatedSurfaceSwatch].allSatisfy(reads),
            opacity < 1
        {
            opacity = min(1, opacity + 0.05)
        }
        return Swatch(accentSwatch.rgb, opacity: opacity)
    }
    public var unlitMark: Color { unlitMarkSwatch.color }

    static let unlitMarkOpacity = 0.55

    public var notGoneSwatch: Swatch { isDark ? Swatch(0xFF9F_0A) : Swatch(0xB350_00) }
    public var notGone: Color { notGoneSwatch.color }

    // MARK: Surfaces

    public var background: Color { backgroundSwatch.color }
    public var backgroundSwatch: Swatch { isDark ? Swatch(0x1214_1A) : Swatch(0xF2F2_F7) }

    public var contentSurface: Color { contentSurfaceSwatch.color }
    public var contentSurfaceSwatch: Swatch { isDark ? Swatch(0x1C1C_1E) : Swatch(0xFFFF_FF) }

    public var elevatedSurface: Color { elevatedSurfaceSwatch.color }
    public var elevatedSurfaceSwatch: Swatch {
        isDark ? Swatch(0xFFFF_FF, opacity: 0.05).over(backgroundSwatch) : Swatch(0xFFFF_FF)
    }

    public var quotedFill: Color {
        isDark ? Color(rgb: 0xFFFF_FF, opacity: 0.05) : Color(rgb: 0x0000_00, opacity: 0.04)
    }

    // MARK: Text

    public var primaryText: Color { primaryTextSwatch.color }
    public var primaryTextSwatch: Swatch { isDark ? Swatch(0xFFFF_FF) : Swatch(0x0000_00) }

    public var secondaryText: Color { secondaryTextSwatch.color }
    public var secondaryTextSwatch: Swatch { grey(isDark ? 0.75 : 0.85) }

    public var tertiaryText: Color { tertiaryTextSwatch.color }
    public var tertiaryTextSwatch: Swatch { grey(isDark ? 0.62 : 0.79) }

    public var timestampText: Color { timestampTextSwatch.color }
    public var timestampTextSwatch: Swatch { grey(isDark ? 0.75 : 0.92) }

    public var quaternaryText: Color { quaternaryTextSwatch.color }
    public var quaternaryTextSwatch: Swatch { grey(isDark ? 0.52 : 0.74) }

    private func grey(_ opacity: Double) -> Swatch {
        isDark
            ? Swatch(0xEBEB_F5, opacity: adjusted(opacity))
            : Swatch(0x3C3C_43, opacity: adjusted(opacity))
    }

    // MARK: Lines and fills

    public var separator: Color { separatorSwatch.color }
    public var separatorSwatch: Swatch {
        isDark
            ? Swatch(0x5454_58, opacity: adjusted(0.5))
            : Swatch(0x3C3C_43, opacity: adjusted(0.29))
    }

    public var fieldBorder: Color { fieldBorderSwatch.color }
    public var fieldBorderSwatch: Swatch {
        isDark
            ? Swatch(0x8E8E_93, opacity: 1)
            : Swatch(0x3C3C_43, opacity: adjusted(0.6))
    }

    public var fieldFill: Color { fieldFillSwatch.color }
    public var fieldFillSwatch: Swatch {
        Swatch(0x7878_80, opacity: adjustedFill(0.14))
    }

    public var neutralFill: Color { neutralFillSwatch.color }
    public var neutralFillSwatch: Swatch {
        Swatch(0x7878_80, opacity: adjustedFill(isDark ? 0.24 : 0.16))
    }

    public var neutralFillStrong: Color { neutralFillStrongSwatch.color }
    public var neutralFillStrongSwatch: Swatch {
        Swatch(0x7878_80, opacity: adjustedFill(isDark ? 0.30 : 0.20))
    }

    public var avatarFill: Color { avatarFillSwatch.color }
    public var avatarFillSwatch: Swatch {
        isDark ? neutralFillSwatch : Swatch(0x7878_80, opacity: adjustedFill(0.08))
    }

    public var avatarFillStrong: Color { avatarFillStrongSwatch.color }
    public var avatarFillStrongSwatch: Swatch {
        isDark ? neutralFillStrongSwatch : Swatch(0x7878_80, opacity: adjustedFill(0.12))
    }

    public var neutralText: Color { neutralTextSwatch.color }
    public var neutralTextSwatch: Swatch { grey(isDark ? 0.75 : 0.85) }

    public var badgeFill: Color { badgeFillSwatch.color }
    public var badgeFillSwatch: Swatch { Swatch(0x7878_80, opacity: adjustedFill(0.26)) }
}
