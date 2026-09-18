import CarpenterKit
import SwiftUI

// Compiled only into a debug build. Gating the *call site* is not enough: the view is still
// compiled, so its words reach the shipped binary and the string catalogue a translator
// works from. Measured 2026-09-15 — `strings` on a Release build returned "Blur every
// photo", "Rotate mailbox share" and "Show message delay".
#if DEBUG

#if canImport(CoreHaptics)
    import CoreHaptics
#endif

struct HapticsProbeView: View {
    @Environment(\.palette) private var palette
    @Environment(\.hapticsEnabled) private var hapticsEnabled

    @State private var commits = 0
    @State private var refusals = 0
    @State private var failures = 0

    private var supportsHaptics: Bool {
        #if canImport(CoreHaptics)
            CHHapticEngine.capabilitiesForHardware().supportsHaptics
        #else
            false
        #endif
    }

    private var lowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    var body: some View {
        List {
            Section {
                state(
                    "Taptic Engine", ok: supportsHaptics,
                    yes: Text("Present", bundle: .module),
                    no: Text("Absent — nothing can play here", bundle: .module))
                state(
                    "Low Power Mode", ok: !lowPowerMode,
                    yes: Text("Off", bundle: .module),
                    no: Text("On — the system silences haptics", bundle: .module))
                state(
                    "Haptics setting", ok: hapticsEnabled,
                    yes: Text("On", bundle: .module),
                    no: Text("Off in Behavior", bundle: .module))
            } header: {
                Text("What could silence them", bundle: .module)
            } footer: {
                Text(
                    "System Haptics, in Settings → Sounds & Haptics, can also silence them. No API reports it, so it is the answer left when these three are green.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                fire(Text("Commit", bundle: .module), detail: Text("Sending, posting, reacting", bundle: .module)) {
                    commits += 1
                }
                fire(Text("Refusal", bundle: .module), detail: Text("The app declining something", bundle: .module)) {
                    refusals += 1
                }
                fire(Text("Failure", bundle: .module), detail: Text("Something went wrong", bundle: .module)) {
                    failures += 1
                }
            } header: {
                Text("Play one", bundle: .module)
            } footer: {
                Text(
                    "These go through the same path the app uses, the member's own switch included — so what you feel here is what the app does, not a bypass of it.",
                    bundle: .module)
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(Text("Haptics", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        .haptic(.commit, trigger: commits)
        .haptic(.refusal, trigger: refusals)
        .haptic(.failure, trigger: failures)
    }

    private func state(_ label: String, ok: Bool, yes: Text, no: Text) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? palette.accentColor : palette.tertiaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).foregroundStyle(palette.primaryText)
                (ok ? yes : no)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(.vertical, 2)
    }

    private func fire(_ title: Text, detail: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsRow(icon: "wave.3.right", title: title, detail: detail)
        }
    }
}

#Preview {
    NavigationStack { HapticsProbeView() }
        .environment(\.palette, Palette(accent: .default, appearance: .dark))
}

#endif
