import CarpenterKit
import SwiftUI

public struct HiddenCommentsSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let hidden: Int
    private let settings: OutpostSettings

    public init(hidden: Int, settings: OutpostSettings) {
        self.hidden = hidden
        self.settings = settings
    }

    public var body: some View {
        NavigationStack {
            List {
                // COPY BEGIN 8f8d7935 [NEEDS HUMAN REVIEW]
                SettingsHeaderCard(
                    icon: "eye.slash.fill",
                    title: hidden == 1
                        ? Text("One comment you cannot see", bundle: .module)
                        : Text("\(hidden) comments you cannot see", bundle: .module),
                    paragraph: Text(
                        "Somebody who wrote under this post keeps their comments to the people they have let into their own Outpost. You are not one of them, so their words are not on your device in any form you can read.",
                        bundle: .module))
                // COPY END 8f8d7935

                // COPY BEGIN ebbea6c3 [NEEDS HUMAN REVIEW]
                Section {
                    point(
                        icon: "lock.fill",
                        title: Text("It is not hidden by this app", bundle: .module),
                        detail: Text(
                            "It is sealed with a key you do not have. Nobody chose to hide it from you in particular, and nobody could show it to you — not the person whose post this is, and not us.",
                            bundle: .module))
                    point(
                        icon: "person.fill.questionmark",
                        title: Text("You are not told who", bundle: .module),
                        detail: Text(
                            "Not their name, not a stand-in name, not how many different people. Only that something is there.",
                            bundle: .module))
                    point(
                        icon: "text.append",
                        title: Text("Why say anything at all", bundle: .module),
                        detail: Text(
                            "Because a conversation with pieces quietly missing is worse than one that says a piece is missing. Comments answer the post rather than each other, so nothing you can read depends on what you cannot.",
                            bundle: .module))
                }
                .groupedRowSurface()
                // COPY END ebbea6c3

                // COPY BEGIN 198639c1 [NEEDS HUMAN REVIEW]
                Section {
                    point(
                        icon: "exclamationmark.triangle.fill",
                        title: Text(
                            "This number is the one thing here you cannot check", bundle: .module),
                        detail: Text(
                            "Everything else in Outpost is proof of itself: you hold the message, you can check its signature, and nothing can claim it says something it does not. This count cannot work that way, because it describes messages you hold no key for. It is a claim by the person whose post this is.",
                            bundle: .module))
                    point(
                        icon: "hand.thumbsdown",
                        title: Text("And why that does not much matter", bundle: .module),
                        detail: Text(
                            "Only the person whose post it is could put a wrong number here, and only with a modified copy of the app. All it would buy them is a misleading footnote shown to somebody who already knows somebody they know. It carries no key, no words and no names, so a wrong number changes what you are told about a gap and nothing else.",
                            bundle: .module))
                }
                .groupedRowSurface()
                // COPY END 198639c1

                // COPY BEGIN 3cbaa876 [NEEDS HUMAN REVIEW]
                Section {
                    NavigationLink {
                        OutpostSettingsView(settings)
                    } label: {
                        SettingsRow(
                            icon: "slider.horizontal.3", tone: .device,
                            title: Text("Review your privacy settings", bundle: .module),
                            subtitle: Text(
                                "Yours work the same way. Closed keeps what you write to the people you have let in.",
                                bundle: .module))
                    }
                }
                .groupedRowSurface()
                // COPY END 3cbaa876
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            // COPY BEGIN 093f8372 [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("Missing comments", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
            // COPY END 093f8372
        }
    }

    private func point(icon: String, title: Text, detail: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(icon, fill: palette.tileFill(.feature))
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                detail
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview("Missing comments") {
        Color.clear.sheet(isPresented: .constant(true)) {
            HiddenCommentsSheet(hidden: 2, settings: OutpostSettings(consent: .open))
        }
        .themed(.default)
    }
#endif
