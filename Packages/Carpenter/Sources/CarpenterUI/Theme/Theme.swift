import CarpenterKit
import SwiftUI

@MainActor
@Observable
public final class ThemeStore {
    private static let storageKey = "theme.accent"

    private let defaults: UserDefaults

    private static let tutorialKey = "theme.tutorialMode"
    private static let hapticsKey = "theme.haptics"
    private static let delayKey = "theme.messageDelay"
    private static let demoKey = "debug.demoConversation"
    private static let demoCountKey = "debug.demoParticipants"
    private static let demoOutpostKey = "debug.demoOutpost"

    public var accent: Accent {
        didSet { defaults.set(accent.rawValue, forKey: Self.storageKey) }
    }

    public var tutorialMode: Bool {
        didSet { defaults.set(tutorialMode, forKey: Self.tutorialKey) }
    }

    public var playsHaptics: Bool {
        didSet { defaults.set(playsHaptics, forKey: Self.hapticsKey) }
    }

    public var showsMessageDelay: Bool {
        didSet { defaults.set(showsMessageDelay, forKey: Self.delayKey) }
    }

    public var demoConversation: Bool {
        didSet { defaults.set(demoConversation, forKey: Self.demoKey) }
    }

    public var demoOutpost: Bool {
        didSet { defaults.set(demoOutpost, forKey: Self.demoOutpostKey) }
    }

    public var demoParticipants: Int {
        didSet {
            demoParticipants = DemoConversation.clamped(demoParticipants)
            defaults.set(demoParticipants, forKey: Self.demoCountKey)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsMessageDelay = defaults.bool(forKey: Self.delayKey)
        demoConversation = defaults.bool(forKey: Self.demoKey)
        demoOutpost = defaults.bool(forKey: Self.demoOutpostKey)
        demoParticipants = DemoConversation.clamped(
            defaults.object(forKey: Self.demoCountKey) as? Int ?? 8)
        tutorialMode = defaults.bool(forKey: Self.tutorialKey)
        playsHaptics = defaults.object(forKey: Self.hapticsKey) as? Bool ?? true
        accent =
            defaults.string(forKey: Self.storageKey)
            .flatMap(Accent.init(rawValue:)) ?? .default
    }
}

@MainActor
@Observable
public final class AppIconStore {
    private static let storageKey = "theme.appIcon"

    private let defaults: UserDefaults

    public var choice: AppIconChoice {
        didSet { defaults.set(choice.rawValue, forKey: Self.storageKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choice =
            defaults.string(forKey: Self.storageKey)
            .flatMap(AppIconChoice.init(rawValue:)) ?? .default
    }
}

extension EnvironmentValues {
    @Entry public var palette = Palette(accent: .default, appearance: .dark)

    @Entry public var bubbleMaxWidth: CGFloat = .infinity

    @Entry public var clock: any Clock = SystemClock()

    @Entry public var stampDevice: DeviceID = DeviceID(rawValue: Data())
}

extension View {
    public func themed(_ accent: Accent) -> some View {
        modifier(ThemedModifier(accent: accent))
    }
}

private struct ThemedModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    let accent: Accent

    private var palette: Palette {
        Palette(
            accent: accent,
            appearance: colorScheme == .dark ? .dark : .light,
            contrast: contrast
        )
    }

    func body(content: Content) -> some View {
        content
            .environment(\.palette, palette)
            .tint(palette.accentColor)
            .background(palette.background)
    }
}

public struct AvatarsShownKey: EnvironmentKey {
    public static let defaultValue = true
}

extension EnvironmentValues {
    public var showsAvatars: Bool {
        get { self[AvatarsShownKey.self] }
        set { self[AvatarsShownKey.self] = newValue }
    }
}

public struct RunAuthorsShownKey: EnvironmentKey {
    public static let defaultValue = true
}

extension EnvironmentValues {
    public var showsRunAuthors: Bool {
        get { self[RunAuthorsShownKey.self] }
        set { self[RunAuthorsShownKey.self] = newValue }
    }
}
