import CarpenterKit
import SwiftUI

extension HapticCue {
    var feedback: SensoryFeedback {
        switch self {
        case .commit: .impact(weight: .light, intensity: 0.7)
        case .refusal: .warning
        case .failure: .error
        }
    }
}

extension EnvironmentValues {
    @Entry public var hapticsEnabled: Bool = true
}

extension View {
    public func haptic<T: Equatable>(_ cue: HapticCue, trigger: T) -> some View {
        modifier(HapticModifier(cue: cue, trigger: trigger))
    }

    public func haptic<T: Equatable>(
        trigger: T, _ cue: @escaping (T, T) -> HapticCue?
    ) -> some View {
        modifier(HapticChoiceModifier(cue: cue, trigger: trigger))
    }
}

private struct HapticModifier<T: Equatable>: ViewModifier {
    @Environment(\.hapticsEnabled) private var enabled
    let cue: HapticCue
    let trigger: T

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { _, _ in enabled ? cue.feedback : nil }
    }
}

private struct HapticChoiceModifier<T: Equatable>: ViewModifier {
    @Environment(\.hapticsEnabled) private var enabled
    let cue: (T, T) -> HapticCue?
    let trigger: T

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { old, new in
            guard enabled else { return nil }
            return cue(old, new)?.feedback
        }
    }
}

extension View {
    public func spokenCharacterByCharacter(_ phrase: String) -> some View {
        accessibilityLabel(Text(verbatim: phrase.map(String.init).joined(separator: ", ")))
    }
}
