import CarpenterKit
import CarpenterMedia
import SwiftUI

#if DEBUG

struct DebugMenuView: View {
    @Environment(\.palette) private var palette
    let actions: DebugActions
    @Binding var demoConversation: Bool
    @Binding var demoParticipants: Int
    @Binding var demoOutpost: Bool
    @Binding var blursEveryPhoto: Bool
    @Binding var showsMessageDelay: Bool

    var body: some View {
        SettingsPage {
            Section {
                Button { Task { await actions.checkMailbox() } } label: {
                    SettingsRow(
                        icon: "tray.full",
                        title: Text("Check mailbox", bundle: .module),
                        detail: Text("Put one packet through CloudKit and report each step", bundle: .module)
                    )
                }

                Button { Task { await actions.rotateMailboxShare() } } label: {
                    SettingsRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: Text("Rotate mailbox share", bundle: .module),
                        detail: Text(
                            "Erase this member's outbox and share it afresh. Every peer then holds a dead offer until the rendezvous heals it.",
                            bundle: .module)
                    )
                }
                Button { Task { await actions.pretendFocus(true) } } label: {
                    SettingsRow(
                        icon: "moon.fill",
                        title: Text("Pretend a Focus is on", bundle: .module),
                        detail: Text(
                            "Report a Focus to the session as the system would. A simulator has no Focus of its own.",
                            bundle: .module)
                    )
                }
                Button { Task { await actions.pretendFocus(false) } } label: {
                    SettingsRow(
                        icon: "moon",
                        title: Text("Pretend the Focus ended", bundle: .module))
                }
                NavigationLink {
                    HapticsProbeView()
                } label: {
                    SettingsRow(
                        icon: "wave.3.right",
                        title: Text("Haptics", bundle: .module),
                        detail: Text("Play each cue, and what could be silencing them", bundle: .module)
                    )
                }
                NavigationLink {
                    StyleTestView()
                } label: {
                    SettingsRow(
                        icon: "ruler",
                        title: Text("Style test", bundle: .module),
                        detail: Text(
                            "Layouts that need more people than the rig has", bundle: .module)
                    )
                }
            } footer: {
                Text(
                    "These are development tools. They are removed before release.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                SettingsToggle(
                    icon: "text.bubble", title: Text("Demo conversation", bundle: .module),
                    detail: Text("A scripted room for pacing and layout", bundle: .module), isOn: $demoConversation)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Participants: \(demoParticipants)", bundle: .module)
                        .foregroundStyle(palette.primaryText)
                    Slider(
                        value: Binding(
                            get: { Double(demoParticipants) },
                            set: { demoParticipants = Int($0.rounded()) }),
                        in: Double(DemoConversation.cap.lowerBound)
                            ... Double(DemoConversation.cap.upperBound),
                        step: 1
                    )
                    .tint(palette.accentColor)
                }
                .disabled(!demoConversation)
                .opacity(demoConversation ? 1 : 0.45)
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text("\(demoParticipants)", bundle: .module))
                SettingsToggle(
                    icon: "rectangle.stack.badge.person.crop", title: Text("Demo Outpost feed", bundle: .module),
                    detail: Text("A scripted feed with tags to filter", bundle: .module), isOn: $demoOutpost)
                SettingsToggle(
                    icon: "eye.slash", title: Text("Blur every photo", bundle: .module),
                    detail: Text("Treat each one as sensitive, to see the blur where the system will not judge", bundle: .module),
                    isOn: $blursEveryPhoto)
            } footer: {
                Text(
                    "Eight people carry the conversation; every participant past eight adds a voice. Capped at 25.",
                    bundle: .module)
            }
            .groupedRowSurface()

            Section {
                SettingsToggle(
                    icon: "timer", title: Text("Show message delay", bundle: .module),
                    isOn: $showsMessageDelay)
            } footer: {
                Text(
                    "Under each arriving message: this device's clock when it landed, minus the sender's stamp. Includes the two clocks' disagreement, so read it against the next one, not on its own.",
                    bundle: .module)
            }
            .groupedRowSurface()
        }
        .listSurfaceHidden()
        .pageBackground()
        .navigationTitle(Text("Debug", bundle: .module))
    }
}

#if DEBUG
    private struct YouPreview: View {
        @State private var accent = Accent.cobalt

        var body: some View {
            NavigationStack {
                YouView(
                    accent: $accent,
                    owner: Fixtures.cassilda,
                    fingerprint: Fixtures.cassilda.id.groupedFingerprint,
                    postCount: 128,
                    audiencePeople: 14,
                    tagCount: 4
                )
            }
            .themed(accent)
        }
    }

    #Preview("45 You — dark") {
        YouPreview().preferredColorScheme(.dark)
    }
#endif

#endif
