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
            // COPY BEGIN 66eb4921 [NEEDS HUMAN REVIEW]
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
            // COPY END 66eb4921

            Section {
                // COPY BEGIN ede6da95 [NEEDS HUMAN REVIEW]
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
                // COPY END ede6da95
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN 06717d83 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Supporter", bundle: .module))
        // COPY END 06717d83
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: showsBadge) { _, shows in
            Task { await settings.onShowBadge(shows) }
        }
    }
}
