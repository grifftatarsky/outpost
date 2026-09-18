import SwiftUI
import Testing

@testable import CarpenterKit
@testable import CarpenterUI

@Suite("WCAG AA contrast")
struct ContrastAuditTests {
    private static let appearances: [Appearance] = [.dark, .light]
    private static let contrasts: [ColorSchemeContrast] = [.standard, .increased]

    private func palettes() -> [Palette] {
        Self.appearances.flatMap { appearance in
            Self.contrasts.map { Palette(accent: .cobalt, appearance: appearance, contrast: $0) }
        }
    }

    @Test("Every text weight is readable on every surface it is drawn on")
    func textPassesOnEverySurface() {
        for palette in palettes() {
            let surfaces: [(String, Swatch)] = [
                ("background", palette.backgroundSwatch),
                ("content", palette.contentSurfaceSwatch),
                ("elevated", palette.elevatedSurfaceSwatch),
            ]
            let texts: [(String, Swatch)] = [
                ("primary", palette.primaryTextSwatch),
                ("secondary", palette.secondaryTextSwatch),
                ("tertiary", palette.tertiaryTextSwatch),
                ("quaternary", palette.quaternaryTextSwatch),
                ("neutral", palette.neutralTextSwatch),
            ]

            for (surfaceName, surface) in surfaces {
                for (textName, text) in texts {
                    let ratio = WCAG.contrastRatio(text.over(surface), surface)
                    #expect(
                        ratio >= WCAG.Requirement.normalText.ratio,
                        """
                        \(textName) on \(surfaceName) in \(palette.appearance)/\(palette.contrast) \
                        measured \(String(format: "%.2f", ratio)), needs 4.5
                        """)
                }
            }
        }
    }

    @Test("A text field's edge is visible against what it sits on")
    func fieldBorderIdentifiesItsControl() {
        for palette in palettes() {
            for (name, surface) in [
                ("elevated", palette.elevatedSurfaceSwatch),
                ("background", palette.backgroundSwatch),
            ] {
                let border = palette.fieldBorderSwatch.over(surface)
                let ratio = WCAG.contrastRatio(border, surface)
                #expect(
                    ratio >= WCAG.Requirement.userInterface.ratio,
                    """
                    field border on \(name) in \(palette.appearance)/\(palette.contrast) measured \
                    \(String(format: "%.2f", ratio)), needs 3.0
                    """)
            }
        }
    }

    @Test("Text on the accent tint is readable for every accent")
    func textOnAccentTintPasses() {
        for accent in Accent.allCases {
            for appearance in Self.appearances {
                let palette = Palette(accent: accent, appearance: appearance)
                let tint = palette.accentTintSwatch.over(palette.backgroundSwatch)
                let ratio = WCAG.contrastRatio(palette.textOnAccentTintSwatch.over(tint), tint)
                #expect(
                    ratio >= WCAG.Requirement.normalText.ratio,
                    "\(accent) \(appearance) tint measured \(String(format: "%.2f", ratio))")
            }
        }
    }

    @Test("The accent is readable as text on every surface it is drawn on")
    func accentAsTextPasses() {
        for accent in Accent.allCases {
            for appearance in Self.appearances {
                let palette = Palette(accent: accent, appearance: appearance)
                let grounds: [(String, Swatch)] = [
                    ("background", palette.backgroundSwatch),
                    ("content", palette.contentSurfaceSwatch),
                    ("elevated", palette.elevatedSurfaceSwatch),
                ]
                for (name, ground) in grounds {
                    let ratio = WCAG.contrastRatio(palette.accentSwatch, ground)
                    #expect(
                        ratio >= WCAG.Requirement.normalText.ratio,
                        """
                        \(accent) \(appearance) as text on \(name) measured \
                        \(String(format: "%.2f", ratio)), needs 4.5
                        """)
                }
            }
        }
    }

    @Test("The time on a room row is readable in both appearances")
    func timestampPasses() {
        for appearance in Self.appearances {
            for contrast in Self.contrasts {
                let palette = Palette(accent: .default, appearance: appearance, contrast: contrast)
                let ground = palette.backgroundSwatch
                let ratio = WCAG.contrastRatio(palette.timestampTextSwatch.over(ground), ground)
                #expect(ratio >= WCAG.Requirement.normalText.ratio)
            }
        }
    }

    @Test("An avatar's initial reads against its disc, on the grounds a disc sits on")
    func avatarInitialPasses() {
        for appearance in Self.appearances {
            let palette = Palette(accent: .default, appearance: appearance)
            for (name, ground) in [
                ("background", palette.backgroundSwatch), ("content", palette.contentSurfaceSwatch),
            ] {
                let disc = palette.avatarFillSwatch.over(ground)
                let letter = palette.neutralTextSwatch.over(ground)
                let ratio = WCAG.contrastRatio(letter, disc)
                #expect(
                    ratio >= WCAG.Requirement.normalText.ratio,
                    "an initial on its disc over \(name) in \(appearance) measured \(String(format: "%.2f", ratio))")
            }
        }
    }

    @Test("Lightening the disc is light-mode only, because in dark it would lower the contrast")
    func avatarDiscIsLighterOnlyInLight() {
        let light = Palette(accent: .default, appearance: .light)
        let dark = Palette(accent: .default, appearance: .dark)
        #expect(light.avatarFillSwatch.opacity < light.neutralFillSwatch.opacity)
        #expect(dark.avatarFillSwatch == dark.neutralFillSwatch)
    }

    @Test("The not-sent mark reads against every ground a transcript is drawn on")
    func notGoneMarkPasses() {
        for accent in Accent.allCases {
            for appearance in Self.appearances {
                let palette = Palette(accent: accent, appearance: appearance)
                for ground in [palette.backgroundSwatch, palette.contentSurfaceSwatch] {
                    let ratio = WCAG.contrastRatio(palette.notGoneSwatch, ground)
                    #expect(
                        ratio >= WCAG.Requirement.normalText.ratio,
                        "\(appearance): the not-sent mark measured \(String(format: "%.2f", ratio))")
                }
            }
        }
    }

    private func everyPalette() -> [Palette] {
        Accent.allCases.flatMap { accent in
            Self.appearances.flatMap { appearance in
                Self.contrasts.map { Palette(accent: accent, appearance: appearance, contrast: $0) }
            }
        }
    }

    private func grounds(_ palette: Palette) -> [(String, Swatch)] {
        [
            ("background", palette.backgroundSwatch), ("content", palette.contentSurfaceSwatch),
            ("elevated", palette.elevatedSurfaceSwatch),
        ]
    }

    @Test("The destructive colour reads as text on every ground and every card it is drawn on")
    func destructiveReadsAsText() {
        for palette in everyPalette() {
            for (name, ground) in grounds(palette) {
                for (surface, swatch) in [("", ground), ("a card over ", palette.fieldFillSwatch.over(ground))] {
                    let ratio = WCAG.contrastRatio(palette.destructiveSwatch, swatch)
                    #expect(
                        ratio >= WCAG.Requirement.normalText.ratio,
                        """
                        destructive on \(surface)\(name) in \(palette.appearance)/\(palette.contrast) \
                        measured \(String(format: "%.2f", ratio))
                        """)
                }
            }
        }
    }

    @Test("A bordered destructive action's label reads on its tinted capsule")
    func destructiveActionLabelReads() {
        for palette in everyPalette() {
            #expect(
                Palette.secondaryActionReads(
                    palette.destructiveActionLabelSwatch, accent: palette.destructiveSwatch,
                    grounds: palette.secondaryActionGrounds),
                "\(palette.appearance)/\(palette.contrast): the destructive label does not read on its capsule")
        }
    }

    @Test("Text on a card or a chip reads, with Increase Contrast on and off")
    func textOnFillsReads() {
        for palette in everyPalette() {
            let texts: [(String, Swatch)] = [
                ("primary", palette.primaryTextSwatch), ("secondary", palette.secondaryTextSwatch),
                ("tertiary", palette.tertiaryTextSwatch), ("neutral", palette.neutralTextSwatch),
            ]
            for (groundName, ground) in grounds(palette) {
                for (fillName, fill) in [
                    ("card", palette.fieldFillSwatch), ("chip", palette.neutralFillSwatch),
                    ("strong chip", palette.neutralFillStrongSwatch),
                ] {
                    let surface = fill.over(ground)
                    let onCard = fillName == "card" ? [("accent label", palette.secondaryActionLabelSwatch)] : []
                    for (textName, text) in texts + onCard {
                        let ratio = WCAG.contrastRatio(text.over(surface), surface)
                        #expect(
                            ratio >= WCAG.Requirement.normalText.ratio,
                            """
                            \(textName) on a \(fillName) over \(groundName), \(palette.accent) \
                            \(palette.appearance)/\(palette.contrast), measured \(String(format: "%.2f", ratio))
                            """)
                    }
                }
            }
        }
    }

    @Test("Increase Contrast raises a fill by the step iOS itself uses, not to a slab")
    func increasedContrastFillsFollowTheSystem() {
        for appearance in Self.appearances {
            let standard = Palette(accent: .default, appearance: appearance)
            let increased = Palette(accent: .default, appearance: appearance, contrast: .increased)
            for (name, low, high) in [
                ("field", standard.fieldFillSwatch, increased.fieldFillSwatch),
                ("neutral", standard.neutralFillSwatch, increased.neutralFillSwatch),
                ("strong", standard.neutralFillStrongSwatch, increased.neutralFillStrongSwatch),
                ("badge", standard.badgeFillSwatch, increased.badgeFillSwatch),
            ] {
                #expect(
                    abs(high.opacity - low.opacity - Palette.increasedFillStep) < 0.001,
                    "\(name) fill in \(appearance) went from \(low.opacity) to \(high.opacity)")
            }
        }
    }

    @Test("An unlit delivery mark clears the floor for a graphic, and is still lighter than a lit one")
    func unlitMarkReads() {
        for palette in everyPalette() {
            let unlit = palette.unlitMarkSwatch
            #expect(unlit.opacity < 1, "\(palette.accent) \(palette.appearance): unlit and lit are the same")
            for (name, ground) in grounds(palette) {
                let ratio = WCAG.contrastRatio(unlit.over(ground), ground)
                #expect(
                    ratio >= WCAG.Requirement.userInterface.ratio,
                    """
                    an unlit mark on \(name), \(palette.accent) \(palette.appearance), measured \
                    \(String(format: "%.2f", ratio))
                    """)
            }
        }
    }

    @Test("White words over a photo read even when the photo is white, because of the dimming under the glass")
    func mediaOverlayReadsOnAWhitePhoto() {
        let dimmed = Swatch(0x0000_00, opacity: CarpenterMetrics.mediaOverlayDimming).over(Swatch(0xFFFF_FF))
        #expect(WCAG.contrastRatio(Swatch(0xFFFF_FF), dimmed) >= WCAG.Requirement.normalText.ratio)
    }

    @Test("A secondary action's label reads on its tinted capsule, for every accent")
    func secondaryActionLabelPasses() {
        for accent in Accent.allCases {
            for appearance in Self.appearances {
                let palette = Palette(accent: accent, appearance: appearance)
                let label = palette.secondaryActionLabelSwatch
                for ground in palette.secondaryActionGrounds {
                    for opacity in Palette.secondaryActionTintRange {
                        let capsule = Swatch(palette.accentSwatch.rgb, opacity: opacity).over(ground)
                        let ratio = WCAG.contrastRatio(label, capsule)
                        #expect(
                            ratio >= WCAG.Requirement.normalText.ratio,
                            """
                            \(accent) \(appearance): a secondary label on a \(opacity) tint measured \
                            \(String(format: "%.2f", ratio))
                            """)
                    }
                }
            }
        }
    }

    @Test("A secondary action's label is still recognisably the accent")
    func secondaryActionLabelKeepsItsHue() {
        for accent in Accent.allCases where accent != .monochrome {
            for appearance in Self.appearances {
                let palette = Palette(accent: accent, appearance: appearance)
                let label = palette.secondaryActionLabelSwatch
                let spread = max(label.red, label.green, label.blue) - min(label.red, label.green, label.blue)
                #expect(spread > 0.08, "\(accent) \(appearance) secondary label went grey: \(String(label.rgb, radix: 16))")
            }
        }
    }

    @Test("Text on the accent is readable for every accent")
    func textOnAccentPasses() {
        for accent in Accent.allCases {
            for appearance in Self.appearances {
                let palette = Palette(accent: accent, appearance: appearance)
                let ratio = WCAG.contrastRatio(palette.textOnAccentSwatch, palette.accentSwatch)

                #expect(
                    ratio >= WCAG.Requirement.normalText.ratio,
                    "\(accent).\(appearance) draws \(ratio) on its accent"
                )
            }
        }
    }

    @Test("White clears the floor on every filled surface")
    func whiteOnFillPasses() {
        for accent in Accent.allCases {
            for appearance in Self.appearances {
                let palette = Palette(accent: accent, appearance: appearance)
                for (name, swatch) in [
                    ("accent fill", palette.accentFillSwatch),
                    ("sent bubble", palette.sentBubbleSwatch),
                    ("destructive fill", palette.destructiveFillSwatch),
                ] {
                    let ratio = WCAG.contrastRatio(Swatch(0xFFFF_FF), swatch)
                    #expect(
                        ratio >= WCAG.Requirement.normalText.ratio,
                        "\(accent).\(appearance) draws white on its \(name) at \(ratio)"
                    )
                }
            }
        }
    }

    @Test("A filled surface is still recognisably the accent")
    func fillStaysRecognisable() {
        for accent in Accent.allCases where accent != .monochrome {
            for appearance in Self.appearances {
                let palette = Palette(accent: accent, appearance: appearance)
                let fill = palette.accentFillSwatch
                #expect(
                    WCAG.contrastRatio(fill, palette.accentSwatch) < 3,
                    "\(accent).\(appearance) darkened its fill so far it reads as a different colour"
                )
            }
        }
    }

    @Test("A field border is visible as an interface edge")
    func fieldBorderIsVisible() {
        for accent in Accent.allCases {
            for appearance in Self.appearances {
                let palette = Palette(accent: accent, appearance: appearance)
                let ratio = WCAG.contrastRatio(
                    palette.fieldBorderSwatch.over(palette.contentSurfaceSwatch),
                    palette.contentSurfaceSwatch)
                #expect(
                    ratio >= WCAG.Requirement.userInterface.ratio,
                    "\(accent).\(appearance) draws a field border at \(ratio)"
                )
            }
        }
    }

    @Test("A field's border is visible against the fill it encloses")
    func fieldBorderClearsItsOwnFill() {
        for accent in Accent.allCases {
            for appearance in Self.appearances {
                let palette = Palette(accent: accent, appearance: appearance)
                for (name, surface) in [
                    ("content", palette.contentSurfaceSwatch),
                    ("ground", palette.backgroundSwatch),
                ] {
                    let fill = palette.fieldFillSwatch.over(surface)
                    let ratio = WCAG.contrastRatio(palette.fieldBorderSwatch.over(fill), fill)
                    #expect(
                        ratio >= WCAG.Requirement.userInterface.ratio,
                        "\(accent).\(appearance) draws a field edge on its own fill over \(name) at \(ratio)"
                    )
                }
            }
        }
    }

    @Test("The badge on a room row carries its name")
    func badgeCarriesItsLabel() {
        for accent in Accent.allCases {
            for appearance in Self.appearances {
                let palette = Palette(accent: accent, appearance: appearance)
                let fill = palette.badgeFillSwatch.over(palette.backgroundSwatch)
                let ratio = WCAG.contrastRatio(palette.primaryTextSwatch.over(fill), fill)
                #expect(
                    ratio >= WCAG.Requirement.normalText.ratio,
                    "\(accent).\(appearance) draws a badge label at \(ratio)"
                )
            }
        }
    }

    @Test("Each accent carries the foreground it contrasts with best")
    func foregroundIsChosenPerAccent() {
        var black: Set<String> = []

        for accent in Accent.allCases {
            for appearance in Self.appearances {
                let palette = Palette(accent: accent, appearance: appearance)
                let chosen = palette.textOnAccentSwatch
                let white = Swatch(0xFFFF_FF)

                let stronger =
                    WCAG.contrastRatio(white, palette.accentSwatch)
                    >= WCAG.contrastRatio(Swatch(0x0000_00), palette.accentSwatch)
                    ? white : Swatch(0x0000_00)
                #expect(chosen == stronger, "\(accent).\(appearance) did not take the stronger pair")

                if chosen.rgb == 0 { black.insert("\(accent).\(appearance)") }
            }
        }

        #expect(
            black == [
                "cobalt.dark", "verdigris.dark", "signalAmber.dark", "oxblood.dark",
                "aubergine.dark", "hangarSlate.dark", "oliveDrab.dark", "monochrome.dark",
            ])
    }
}

@Suite("Contrast arithmetic")
struct WCAGMathTests {
    @Test("Black on white is the maximum ratio")
    func extremes() {
        #expect(abs(WCAG.contrastRatio(Swatch(0x0000_00), Swatch(0xFFFF_FF)) - 21) < 0.01)
        #expect(abs(WCAG.contrastRatio(Swatch(0xFFFF_FF), Swatch(0xFFFF_FF)) - 1) < 0.01)
    }

    @Test("The ratio does not depend on which way round the pair is given")
    func symmetric() {
        let a = Swatch(0x3C3C_43)
        let b = Swatch(0xF2F2_F7)
        #expect(WCAG.contrastRatio(a, b) == WCAG.contrastRatio(b, a))
    }

    @Test("A translucent colour composites to what is actually drawn")
    func compositing() {
        let half = Swatch(0x0000_00, opacity: 0.5).over(Swatch(0xFFFF_FF))
        #expect(half.rgb == 0x8080_80)
        #expect(half.opacity == 1)

        #expect(Swatch(0x1234_56, opacity: 1).over(Swatch(0xFFFF_FF)).rgb == 0x1234_56)
        #expect(Swatch(0x1234_56, opacity: 0).over(Swatch(0xABCD_EF)).rgb == 0xABCD_EF)
    }

    @Test("Measured against values that can be checked by hand")
    func knownValues() {
        #expect(abs(WCAG.contrastRatio(Swatch(0x7676_76), Swatch(0xFFFF_FF)) - 4.54) < 0.01)
        #expect(abs(WCAG.contrastRatio(Swatch(0x8E8E_93), Swatch(0xFFFF_FF)) - 3.26) < 0.01)
        #expect(abs(WCAG.contrastRatio(Swatch(0x5959_59), Swatch(0xFFFF_FF)) - 7.00) < 0.01)

        #expect(WCAG.passes(Swatch(0x7676_76), on: Swatch(0xFFFF_FF), at: .normalText))
        #expect(!WCAG.passes(Swatch(0x8E8E_93), on: Swatch(0xFFFF_FF), at: .normalText))
        #expect(WCAG.passes(Swatch(0x8E8E_93), on: Swatch(0xFFFF_FF), at: .largeText))
    }
}

@Suite("The sent bubble carries white text")
struct SentBubbleContrastTests {
    @Test("White clears AA on every accent, in both appearances")
    func whiteIsLegibleEverywhere() {
        for accent in Accent.allCases {
            for appearance in [Appearance.light, Appearance.dark] {
                let palette = Palette(accent: accent, appearance: appearance)
                let ratio = WCAG.contrastRatio(Swatch(0xFFFF_FF), palette.sentBubbleSwatch)

                #expect(
                    ratio >= WCAG.Requirement.normalText.ratio,
                    "white on \(accent.displayName) in \(appearance) is \(ratio)")
            }
        }
    }

    @Test("The bubble still reads as the accent the member chose")
    func theAccentSurvivesDarkening() {
        for accent in Accent.allCases {
            for appearance in [Appearance.light, Appearance.dark] {
                let palette = Palette(accent: accent, appearance: appearance)
                let bubble = palette.sentBubbleSwatch

                #expect(
                    WCAG.contrastRatio(bubble, Swatch(0x0000_00)) > 1.5,
                    "\(accent.displayName) in \(appearance) darkened to near-black")
            }
        }
    }
}
