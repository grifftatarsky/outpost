import CarpenterKit
import SwiftUI

@MainActor
@Observable
public final class SafetyPreferences {
    private static let blurKey = "safety.blursSensitiveMedia"
    private static let denyKey = "safety.blocksKnownAbusers"
    private static let debugBlurKey = "debug.blursEveryPhoto"

    private let defaults: UserDefaults

    public var blursSensitiveMedia: Bool {
        didSet { defaults.set(blursSensitiveMedia, forKey: Self.blurKey) }
    }

    public var blocksKnownAbusers: Bool {
        didSet { defaults.set(blocksKnownAbusers, forKey: Self.denyKey) }
    }

    public var blursEveryPhoto: Bool {
        didSet { defaults.set(blursEveryPhoto, forKey: Self.debugBlurKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        blursSensitiveMedia = defaults.object(forKey: Self.blurKey) as? Bool ?? true
        blocksKnownAbusers = defaults.object(forKey: Self.denyKey) as? Bool ?? true
        blursEveryPhoto = defaults.bool(forKey: Self.debugBlurKey)
    }
}

extension EnvironmentValues {
    @Entry public var blursSensitiveMedia: Bool = true
}
