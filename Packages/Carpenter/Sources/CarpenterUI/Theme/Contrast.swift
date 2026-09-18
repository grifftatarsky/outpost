import SwiftUI

public struct Swatch: Hashable, Sendable {
    public let rgb: UInt32
    public let opacity: Double

    public init(_ rgb: UInt32, opacity: Double = 1) {
        self.rgb = rgb
        self.opacity = opacity
    }

    public var color: Color { Color(rgb: rgb, opacity: opacity) }

    public var red: Double { Double((rgb >> 16) & 0xFF) / 255 }
    public var green: Double { Double((rgb >> 8) & 0xFF) / 255 }
    public var blue: Double { Double(rgb & 0xFF) / 255 }

    public func over(_ backdrop: Swatch) -> Swatch {
        func blend(_ top: Double, _ bottom: Double) -> Double {
            top * opacity + bottom * (1 - opacity)
        }
        let r = UInt32((blend(red, backdrop.red) * 255).rounded())
        let g = UInt32((blend(green, backdrop.green) * 255).rounded())
        let b = UInt32((blend(blue, backdrop.blue) * 255).rounded())
        return Swatch((r << 16) | (g << 8) | b)
    }

    public func darkened(by amount: Double) -> Swatch {
        let factor = max(0, min(1, 1 - amount))
        let r = UInt32((red * factor * 255).rounded())
        let g = UInt32((green * factor * 255).rounded())
        let b = UInt32((blue * factor * 255).rounded())
        return Swatch((r << 16) | (g << 8) | b, opacity: opacity)
    }

    public func lightened(by amount: Double) -> Swatch {
        let mix = max(0, min(1, amount))
        func lift(_ value: Double) -> UInt32 { UInt32(((value + (1 - value) * mix) * 255).rounded()) }
        return Swatch((lift(red) << 16) | (lift(green) << 8) | lift(blue), opacity: opacity)
    }

    public var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

public enum WCAG {
    public static func contrastRatio(_ a: Swatch, _ b: Swatch) -> Double {
        let first = a.relativeLuminance
        let second = b.relativeLuminance
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public enum Requirement: Hashable, Sendable {
        case normalText
        case largeText
        case userInterface

        public var ratio: Double {
            switch self {
            case .normalText: 4.5
            case .largeText, .userInterface: 3.0
            }
        }
    }

    public static func passes(
        _ a: Swatch, on b: Swatch, at requirement: Requirement
    ) -> Bool {
        contrastRatio(a, b) >= requirement.ratio
    }
}
