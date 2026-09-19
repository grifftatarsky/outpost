import CarpenterKit
import SwiftUI

struct SupporterView: View {
    @Environment(\.palette) private var palette

    let settings: SupporterSettings

    @State private var showsBadge: Bool
    @State private var sharesBadge: Bool

    init(settings: SupporterSettings) {
        self.settings = settings
        _showsBadge = State(initialValue: settings.showsBadge)
        _sharesBadge = State(initialValue: settings.sharesBadge)
    }

    var body: some View {
        SettingsPage {
            SettingsHeaderCard(
                icon: "party.popper.fill",
                title: Text("Supporter", bundle: .module),
                paragraph: settings.standingSentence)

            if settings.standing.isSupporter {
                Section {
                    SettingsToggle(
                        icon: "checkmark.seal.fill",
                        title: Text("Show it on your picture", bundle: .module),
                        isOn: $showsBadge)
                } footer: {
                    Text(
                        "A small mark on your own picture, on this device and your others. Nobody else is told either way.",
                        bundle: .module)
                }
                .groupedRowSurface()

                Section {
                    SettingsToggle(
                        icon: "person.2.fill",
                        title: Text("Show it to other people", bundle: .module),
                        isOn: $sharesBadge)
                } footer: {
                    Text(
                        "Everyone in your conversations sees it, and so does anyone who can read your Outpost. Turning it off tells them to stop drawing it.",
                        bundle: .module)
                }
                .groupedRowSurface()
            }

            Section {
                Label {
                    Text(
                        "Supporters pay for the time it takes to build what comes next, starting with Packs.",
                        bundle: .module)
                } icon: {
                    Image(systemName: "hammer.fill").foregroundStyle(palette.accentColor)
                }
                Label {
                    Text(
                        "A Pack you turn on works for everyone in that conversation, whether they support or not.",
                        bundle: .module)
                } icon: {
                    Image(systemName: "person.2.fill").foregroundStyle(palette.accentColor)
                }
            } header: {
                Text("What it pays for", bundle: .module).sectionHeading()
            }
            .groupedRowSurface()
        }
        .listSurfaceHidden()
        .pageBackground()
        .navigationTitle(Text("Supporter", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: showsBadge) { _, shows in
            Task { await settings.onShowBadge(shows) }
        }
        .onChange(of: sharesBadge) { _, shares in
            Task { await settings.onShareBadge(shares) }
        }
    }
}
