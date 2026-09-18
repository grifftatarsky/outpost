import SwiftUI

public struct WelcomeTourView: View {
    @Environment(\.palette) private var palette

    private let onContinue: () -> Void

    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    private struct Panel: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let body: LocalizedStringKey
        let icon: String
    }

    private var panels: [Panel] {
        [
            Panel(
                id: 0,
                title: "You do not have an account",
                body:
                    "Your device makes a key, and that key is you. No sign-up, no password, no phone number, and nobody can look you up.",
                icon: "key"),
            Panel(
                id: 1,
                title: "Where your messages go",
                body:
                    "Straight to the people you wrote to. Phones sleep, so a mailbox holds what is in flight — messages, photos and clips alike — sealed, addressed to a code that changes, and deleted once everyone has collected.",
                icon: "tray"),
            Panel(
                id: 2,
                title: "Who has your messages",
                body:
                    "You, and the people you sent them to. Nobody else can read them — not us, not Apple — because nothing readable is ever uploaded.",
                icon: "lock"),
            Panel(
                id: 3,
                title: "Compared to other apps",
                body:
                    "Standard messaging apps, including the security-focused ones: at best they cannot read your messages but still know who you talk to and how often. At worst they hold a key to everything. Here there is no account for any of that to hang on.",
                icon: "arrow.left.arrow.right"),
            Panel(
                id: 4,
                title: "What it costs",
                body:
                    "Your keys ride your iCloud Keychain, so a new device picks them up by itself. If that goes too, the recovery key you download is the only way back — there is no reset link and nobody to ask. It brings you back, not your conversations: those are asked for from the people who were in them.",
                icon: "exclamationmark.triangle"),
            Panel(
                id: 5,
                title: "What it will ask you",
                body:
                    "Two things, each when it comes up and never at launch. Notifications, so a message can announce itself. And the system's photo picker, which shows your library to you and hands over only what you choose — it never asks for the library itself. There is no camera in the app.",
                icon: "hand.raised"),
        ]
    }

    @State private var page = 0

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(panels) { panel in
                    VStack(spacing: 20) {
                        Spacer()

                        Image(systemName: panel.icon)
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(palette.accentColor)

                        Text(panel.title, bundle: .module)
                            .font(CarpenterFont.navigationTitle)
                            .foregroundStyle(palette.primaryText)
                            .multilineTextAlignment(.center)

                        Text(panel.body, bundle: .module)
                            .font(CarpenterFont.rowDetail)
                            .foregroundStyle(palette.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        if panel.id == panels.count - 1 {
                            Text(
                                "New here? Turn on Tutorial mode in You — every screen gains a ? that explains its buttons.",
                                bundle: .module
                            )
                            .font(CarpenterFont.footnote)
                            .foregroundStyle(palette.tertiaryText)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 34)
                    .tag(panel.id)
                }
            }
            #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .always))
            #endif

            Group {
                if page == panels.count - 1 {
                    Button(action: onContinue) {
                        Text("Get started", bundle: .module)
                            .font(CarpenterFont.button)
                            .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accentFill)
                } else {
                    Button(action: onContinue) {
                        Text("Skip", bundle: .module)
                            .font(CarpenterFont.button)
                            .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .tint(palette.accentColor)
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.bottom, 22)
        }
        .background(palette.background)
    }
}

#if DEBUG
    #Preview("Welcome — dark") {
        WelcomeTourView(onContinue: {}).themed(.default).preferredColorScheme(.dark)
    }

    #Preview("Welcome — light") {
        WelcomeTourView(onContinue: {}).themed(.default).preferredColorScheme(.light)
    }
#endif
