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
            // COPY BEGIN 29dbb6ae [NEEDS HUMAN REVIEW]
            SettingsHeaderCard(
                icon: "hand.tap.fill",
                title: Text("Behavior", bundle: .module),
                paragraph: Text(
                    "Small things the app does as you use it. Each one is this device's alone.",
                    bundle: .module))
            // COPY END 29dbb6ae

            // COPY BEGIN d8389a2c [NEEDS HUMAN REVIEW]
            Section {
                SettingsToggle(
                    icon: "hand.tap.fill", title: Text("Haptics", bundle: .module),
                    isOn: $playsHaptics)
                SettingsToggle(
                    icon: "questionmark.circle.fill",
                    title: Text("Help on every screen", bundle: .module), isOn: $tutorialMode)
            }
            .groupedRowSurface()
            // COPY END d8389a2c

            #if os(iOS)
                InviteScanningSetting()
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN befc30a8 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Behavior", bundle: .module))
        // COPY END befc30a8
        .toolbarTitleDisplayMode(.inline)
    }
}
