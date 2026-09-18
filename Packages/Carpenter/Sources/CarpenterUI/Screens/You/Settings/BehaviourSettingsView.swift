import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

struct BehaviourSettingsView: View {
    @Environment(\.palette) private var palette

    @Binding var playsHaptics: Bool
    @Binding var tutorialMode: Bool

    var body: some View {
        List {
            SettingsHeaderCard(
                icon: "hand.tap.fill",
                title: Text("Behavior", bundle: .module),
                paragraph: Text(
                    "Small things the app does as you use it. Each one is this device's alone.",
                    bundle: .module))

            Section {
                SettingsToggle(
                    icon: "hand.tap.fill", title: Text("Haptics", bundle: .module),
                    isOn: $playsHaptics)
                SettingsToggle(
                    icon: "questionmark.circle.fill",
                    title: Text("Help on every screen", bundle: .module), isOn: $tutorialMode)
            }
            .groupedRowSurface()

            #if os(iOS)
                InviteScanningSetting()
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(Text("Behavior", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
    }
}
