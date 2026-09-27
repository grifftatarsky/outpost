import CarpenterKit
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

    // COPY BEGIN 92143e53 [NEEDS HUMAN REVIEW]
    private var panels: [Panel] {
        [
            Panel(
                id: 0,
                title: "You do not have a key",
                body:
                    "Your key is your identity, and it lives in your own Keychain. There is no account, and no one can look you up.",
                icon: "key"),
            Panel(
                id: 1,
                title: "Message Delivery",
                body:
                    "Messages are delivered straight to their recipients. Your iCloud functions as a mailbox, holding in-flight messages. Everything inside is sealed, and addressed to a rotating key. Once all recipients have collected the message, it's removed, and only on your circle's devices.",
                icon: "tray"),
            Panel(
                id: 2,
                title: "Message Ownership",
                body:
                    "Only you and the people you talk to have your messages. Apple can't read anything, and the \(Branding.displayName) Dev has nothing to do with you after download.",
                icon: "lock"),
            Panel(
                id: 3,
                title: "Compared to Other Apps",
                body:
                    "At best, even security focused apps who can't read your messages still know who you talk to and how often, and that's stored on their servers. At worst, they can read everything. Here, the \(Branding.displayName) Dev has none of your data at all.",
                icon: "arrow.left.arrow.right"),
            Panel(
                id: 4,
                title: "Drawbacks",
                body:
                    "A private and secure architecture does have cons. Your key—identity—lives only on your devices, and a new device gets it when one of yours approves it. If you lose them all, the recovery key is the only way back. So if that's gone, the \(Branding.displayName) Dev has no way to help.\n\nThe recovery key brings back your identity, but the conversations themselves are backfilled by request.",
                icon: "exclamationmark.triangle"),
            Panel(
                id: 5,
                title: "App Permissions",
                body:
                    "\(Branding.displayName) requests permissions, all of which are optional, and customizable. Notifications enable message announcements, Focus enables Do Not Disturb syncing with iOS, and Photos use the system photo picker and hand over only what you select (it does not ask for full access).",
                icon: "hand.raised"),
        ]
    }
    // COPY END 92143e53

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

                        // COPY BEGIN a0ba5304 [HUMAN REVIEWED, UNVERIFIED]
                        if panel.id == panels.count - 1 {
                            Text(
                                "\(Branding.displayName) can be as complicated as you want it to be. But if you forget what your options are, there's Tutorial mode in the You page, which will add a ? on every screen to explain!",
                                bundle: .module
                            )
                            .font(CarpenterFont.footnote)
                            .foregroundStyle(palette.tertiaryText)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                        }
                        // COPY END a0ba5304

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
                    // COPY BEGIN 70d3df21 [HUMAN REVIEWED, UNVERIFIED]
                    Button(action: onContinue) {
                        Text("Start", bundle: .module)
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
                    // COPY END 70d3df21
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
