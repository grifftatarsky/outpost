import CarpenterUI
import SwiftUI

@main
struct CarpenterMain: App {
    #if os(iOS)
        @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    #elseif os(macOS)
        @NSApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    #endif

    @State private var shell = AppShell()

    @ViewBuilder private var root: some View {
        #if DEBUG
            if let shot = SiteShot.requested() {
                SiteShotView(shot)
            } else {
                AppRootView(shell: shell, surface: .window)
            }
        #else
            AppRootView(shell: shell, surface: .window)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            root
                #if os(macOS)
                    .frame(minWidth: 720, minHeight: 520)
                #endif
        }
        #if os(macOS)
            .defaultSize(width: 1_000, height: 720)
            .windowResizability(.contentMinSize)
            .commands { DesktopCommands() }
        #endif

        #if os(macOS)
            Settings {
                AppRootView(shell: shell, surface: .settings)
            }

            Window(Text("How This Works"), id: DesktopCommands.howItWorksWindow) {
                HowItWorksView()
                    .themed(shell.theme.accent)
                    .frame(minWidth: 480, idealWidth: 560, minHeight: 520, idealHeight: 680)
            }
            .windowResizability(.contentSize)
        #endif
    }
}
