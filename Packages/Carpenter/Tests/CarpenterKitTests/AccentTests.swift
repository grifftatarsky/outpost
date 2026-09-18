import SwiftUI
import Testing

@testable import CarpenterKit
@testable import CarpenterUI

@Suite("Accent palette")
struct AccentTests {
    @Test("The palette is the seven designed accents, in board order")
    func paletteOrder() {
        #expect(
            Accent.allCases.map(\.displayName) == [
                "Cobalt", "Verdigris", "Signal Amber", "Oxblood",
                "Aubergine", "Hangar Slate", "Olive Drab", "Monochrome",
            ])
    }

    @Test(
        "Every accent ships its dark and light value",
        arguments: [
            (Accent.cobalt, 0x4D85_FA, 0x2F62_DE),
            (Accent.verdigris, 0x34A7_9B, 0x1476_6C),
            (Accent.signalAmber, 0xE093_2F, 0x945D_0F),
            (Accent.oxblood, 0xCE6C_70, 0xA533_3A),
            (Accent.aubergine, 0x9C7C_D4, 0x7048_BC),
            (Accent.hangarSlate, 0x8296_AB, 0x546A_7E),
            (Accent.oliveDrab, 0x97AC_42, 0x6071_20),
        ]
    )
    func toneValues(accent: Accent, dark: Int, light: Int) {
        #expect(accent.tone(for: .dark).rgb == UInt32(dark))
        #expect(accent.tone(for: .light).rgb == UInt32(light))
    }

    @Test("The incoming-bubble tint is a fixed opacity of the same hue, per appearance")
    func tintOpacity() {
        for accent in Accent.allCases {
            #expect(accent.tone(for: .dark).tintOpacity == 0.22)
            #expect(accent.tone(for: .light).tintOpacity == 0.13)
        }
    }

    @Test("Verdigris is the default, so an unseeded install matches the boards")
    func defaultAccent() {
        #expect(Accent.default == .verdigris)
    }

    @Test("Accents round-trip through their stored representation")
    func codingRoundTrip() throws {
        for accent in Accent.allCases {
            #expect(Accent(rawValue: accent.rawValue) == accent)
        }
    }
}

@Suite("Increased contrast")
struct PaletteContrastTests {
    @Test("Standard contrast leaves the board's values exactly as drawn")
    func standardIsUntouched() {
        for opacity in [0.16, 0.18, 0.26, 0.45, 0.6, 0.8] {
            #expect(Palette.adjusted(opacity, for: .standard) == opacity)
        }
    }

    @Test("Increased contrast strengthens every translucent value")
    func increasedIsStronger() {
        for opacity in [0.16, 0.18, 0.26, 0.45, 0.6, 0.8] {
            #expect(Palette.adjusted(opacity, for: .increased) > opacity)
        }
    }

    @Test("The faintest values gain the most")
    func faintValuesGainMost() {
        let faint = Palette.adjusted(0.16, for: .increased) - 0.16
        let strong = Palette.adjusted(0.8, for: .increased) - 0.8

        #expect(faint > strong)
    }

    @Test("Nothing is pushed past solid")
    func neverExceedsOpaque() {
        for opacity in [0.0, 0.5, 0.95, 1.0] {
            #expect(Palette.adjusted(opacity, for: .increased) <= 1)
        }
    }

    @Test("A palette built with increased contrast differs from one without")
    func paletteCarriesTheSetting() {
        let standard = Palette(accent: .cobalt, appearance: .dark, contrast: .standard)
        let increased = Palette(accent: .cobalt, appearance: .dark, contrast: .increased)

        #expect(standard != increased)
        #expect(standard.contrast == .standard)
        #expect(increased.contrast == .increased)
    }
}
