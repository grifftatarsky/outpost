import CarpenterKit
import SwiftUI

extension EnvironmentValues {
    @Entry public var tapToSwap: (() -> Void)?
}

public struct TapToSwapView: View {
    public enum Trouble: Hashable, Sendable {
        case notAllowed
        case noLocalNetwork
    }

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hapticsEnabled) private var hapticsEnabled

    private let phase: TapSwap.Phase
    private let trouble: Trouble?
    private let onAccept: () -> Void

    public init(phase: TapSwap.Phase, trouble: Trouble?, onAccept: @escaping () -> Void) {
        self.phase = phase
        self.trouble = trouble
        self.onAccept = onAccept
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                phones
                    .accessibilityHidden(true)
                VStack(spacing: 10) {
                    headline
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    detail
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.secondaryText)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                Spacer()
                if phase == .touching, trouble == nil {
                    // COPY BEGIN 2cdcc344 [NEEDS HUMAN REVIEW]
                    Button(action: onAccept) {
                        Text("Swap codes", bundle: .module).primaryAction()
                    }
                    .prominentActionButton()
                    // COPY END 2cdcc344
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
            // COPY BEGIN 79c2ce19 [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("Tap phones", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
            }
            // COPY END 79c2ce19
        }
        .sensoryFeedback(trigger: phase) { old, new in
            hapticsEnabled ? Self.feedback(from: old, to: new) : nil
        }
    }

    private var phones: some View {
        VStack(spacing: gap) {
            Image(systemName: "iphone")
                .rotationEffect(.degrees(180))
            Image(systemName: "iphone")
        }
        .font(.system(size: 64, weight: .light))
        .foregroundStyle(phase == .crowded ? palette.secondaryText : palette.accentColor)
        .overlay {
            if phase == .swapped {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(palette.accentColor)
                    .background(Circle().fill(palette.background))
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: gap)
        .animation(.easeInOut(duration: 0.2), value: phase == .swapped)  // cross-fade only
    }

    private var gap: CGFloat {
        switch phase {
        case .looking(let closest): 16 + 96 * CGFloat(min(max(closest ?? 2, 0), 2) / 2)
        case .crowded: 64
        case .touching, .waitingForThem, .swapped: 4
        }
    }

    // COPY BEGIN d79f5f73 [NEEDS HUMAN REVIEW]
    @ViewBuilder
    private var headline: some View {
        switch (trouble, phase) {
        case (.notAllowed?, _): Text("Nearby Interaction is off", bundle: .module)
        case (.noLocalNetwork?, _): Text("Local Network is off", bundle: .module)
        case (nil, .looking): Text("Hold your iPhone against theirs", bundle: .module)
        case (nil, .crowded): Text("More than one phone is close", bundle: .module)
        case (nil, .touching): Text("Swap codes with this phone?", bundle: .module)
        case (nil, .waitingForThem): Text("Waiting for them", bundle: .module)
        case (nil, .swapped): Text("Codes swapped", bundle: .module)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch (trouble, phase) {
        case (.notAllowed?, _):
            Text(
                "Turn on Nearby Interaction for the app in Settings, under Privacy & Security, so it can tell which phone yours is touching.",
                bundle: .module)
        case (.noLocalNetwork?, _):
            Text(
                "Turn on Local Network for the app in Settings, under Privacy & Security, so the two phones can find each other.",
                bundle: .module)
        case (nil, .looking):
            Text(
                "They need this screen open too. Nothing is shared until each of you taps Swap codes.",
                bundle: .module)
        case (nil, .crowded):
            Text(
                "Hold just your two phones together, away from anybody else doing the same.",
                bundle: .module)
        case (nil, .touching):
            Text(
                "You can move the phones apart now. Your code goes to theirs and theirs comes to yours, directly, once you both tap Swap codes.",
                bundle: .module)
        case (nil, .waitingForThem):
            Text("Nothing is shared until they tap Swap codes too.", bundle: .module)
        case (nil, .swapped):
            Text("Check the characters with them when you add each other.", bundle: .module)
        }
    }
    // COPY END d79f5f73

    static func feedback(from old: TapSwap.Phase, to new: TapSwap.Phase) -> SensoryFeedback? {
        switch new {
        case .touching: old == .touching ? nil : .impact(weight: .heavy)
        case .swapped: old == .swapped ? nil : .success
        case .crowded: old == .crowded ? nil : .warning
        case .waitingForThem: nil
        case .looking(let closest): band(closest) > band(of: old) ? .impact(weight: .light, intensity: 0.6) : nil
        }
    }

    private static func band(_ distance: Double?) -> Int {
        guard let distance else { return 0 }
        return [1.0, 0.5, 0.25].filter { distance <= $0 }.count
    }

    private static func band(of phase: TapSwap.Phase) -> Int {
        guard case .looking(let closest) = phase else { return 0 }
        return band(closest)
    }
}
