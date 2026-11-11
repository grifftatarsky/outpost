import CarpenterKit
import SwiftUI

struct AppIconBadgeSection: View {
    let isOn: Bool
    let meaning: BadgeChoices.Meaning
    let onChange: (Bool) -> Void

    var body: some View {
        // COPY BEGIN f6b865c9 [NEEDS HUMAN REVIEW]
        Section {
            SettingsToggle(
                icon: "app.badge.fill",
                title: Text("Show on the app icon", bundle: .module),
                isOn: Binding(get: { isOn }, set: { onChange($0) }))
        } header: {
            Text("App icon", bundle: .module).sectionHeading()
        } footer: {
            BadgeMeaningLine(meaning: meaning)
        }
        .groupedRowSurface()
        // COPY END f6b865c9
    }
}

struct NotificationsOffSection: View {
    @Environment(\.palette) private var palette

    let onOpenSystemSettings: (() -> Void)?

    var body: some View {
        Section {
            // COPY BEGIN 3a61f89f [NEEDS HUMAN REVIEW]
            if let onOpenSystemSettings {
                Button(action: onOpenSystemSettings) {
                    SettingsRow(
                        icon: "gear", tone: .device,
                        title: Text("Turn on notifications", bundle: .module))
                }
            }
        } footer: {
            Text(
                "Notifications are off for \(Branding.displayName) in Settings, so none of these will arrive until that is turned back on. What you choose here is kept either way.",
                bundle: .module)
                .foregroundStyle(palette.destructive)
            // COPY END 3a61f89f
        }
        .groupedRowSurface()
    }
}
