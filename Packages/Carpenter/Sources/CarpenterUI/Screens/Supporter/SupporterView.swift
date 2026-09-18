import CarpenterKit
import SwiftUI

struct SupporterView: View {
    @Environment(\.palette) private var palette

    let settings: SupporterSettings

    @State private var showsBadge: Bool

    init(settings: SupporterSettings) {
        self.settings = settings
        _showsBadge = State(initialValue: settings.showsBadge)
    }

    var body: some View {
        List {
            SettingsHeaderCard(
                icon: "party.popper.fill",
                title: Text("Supporter", bundle: .module),
                paragraph: settings.standingSentence)

            if settings.standing.isSupporter {
                Section {
                    SettingsToggle(
                        icon: "checkmark.seal.fill",
                        title: Text("Show the badge", bundle: .module),
                        isOn: $showsBadge)
                } footer: {
                    Text(
                        "A small mark on your picture. Everyone in your conversations sees it, and so does anyone who can read your Outpost.",
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
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(Text("Supporter", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: showsBadge) { _, shows in
            Task { await settings.onShowBadge(shows) }
        }
    }
}
