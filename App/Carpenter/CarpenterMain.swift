import SwiftUI

#if DEBUG
    import CarpenterUI
#endif

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
        #endif

        #if os(macOS)
            Settings {
                AppRootView(shell: shell, surface: .settings)
            }
        #endif
    }
}
