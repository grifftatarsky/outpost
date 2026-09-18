import Foundation

public enum Appearance: String, CaseIterable, Hashable, Sendable, Codable {
    case light
    case dark
}

public struct AccentTone: Hashable, Sendable {
    public let rgb: UInt32
    public let tintOpacity: Double

    public init(rgb: UInt32, tintOpacity: Double) {
        self.rgb = rgb
        self.tintOpacity = tintOpacity
    }
}

public enum Accent: String, CaseIterable, Hashable, Sendable, Codable {
    case cobalt
    case verdigris
    case signalAmber
    case oxblood
    case aubergine
    case hangarSlate
    case oliveDrab
    case monochrome

    public static let `default` = Accent.verdigris

    public var displayName: String {
        switch self {
        case .cobalt: String(localized: "Cobalt", bundle: .module, comment: "Accent color name")
        case .verdigris: String(localized: "Verdigris", bundle: .module, comment: "Accent color name")
        case .signalAmber: String(localized: "Signal Amber", bundle: .module, comment: "Accent color name")
        case .oxblood: String(localized: "Oxblood", bundle: .module, comment: "Accent color name")
        case .aubergine: String(localized: "Aubergine", bundle: .module, comment: "Accent color name")
        case .hangarSlate: String(localized: "Hangar Slate", bundle: .module, comment: "Accent color name")
        case .oliveDrab: String(localized: "Olive Drab", bundle: .module, comment: "Accent color name")
        case .monochrome: String(localized: "Monochrome", bundle: .module, comment: "Accent color name")
        }
    }

    public func tone(for appearance: Appearance) -> AccentTone {
        switch appearance {
        case .dark: AccentTone(rgb: darkValue, tintOpacity: Self.darkTintOpacity)
        case .light: AccentTone(rgb: lightValue, tintOpacity: Self.lightTintOpacity)
        }
    }

    public var valuePairDescription: String {
        "#\(Self.hexString(darkValue)) / #\(Self.hexString(lightValue))"
    }

    private static let darkTintOpacity = 0.22
    private static let lightTintOpacity = 0.13

    private var darkValue: UInt32 {
        switch self {
        case .cobalt: 0x4D85_FA
        case .verdigris: 0x34A7_9B
        case .signalAmber: 0xE093_2F
        case .oxblood: 0xCE6C_70
        case .aubergine: 0x9C7C_D4
        case .hangarSlate: 0x8296_AB
        case .oliveDrab: 0x97AC_42
        case .monochrome: 0xE2E4_E9
        }
    }

    private var lightValue: UInt32 {
        switch self {
        case .cobalt: 0x2F62_DE
        case .verdigris: 0x1476_6C
        case .signalAmber: 0x945D_0F
        case .oxblood: 0xA533_3A
        case .aubergine: 0x7048_BC
        case .hangarSlate: 0x546A_7E
        case .oliveDrab: 0x6071_20
        case .monochrome: 0x3A3C_42
        }
    }

    private static func hexString(_ value: UInt32) -> String {
        String(format: "%06X", value)
    }
}
