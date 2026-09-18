import SwiftUI

enum Platform {
    static var isMac: Bool {
        #if os(macOS)
            true
        #else
            false
        #endif
    }
}

extension View {
    @ViewBuilder
    func largeNavigationTitle() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.large)
        #else
            self
        #endif
    }

    @ViewBuilder
    func alwaysEditing() -> some View {
        #if os(iOS)
            environment(\.editMode, .constant(.active))
        #else
            self
        #endif
    }

    @ViewBuilder
    func hidingTabBar() -> some View {
        #if os(iOS)
            toolbar(.hidden, for: .tabBar)
        #else
            self
        #endif
    }
}
