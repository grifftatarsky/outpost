import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(\.palette) private var palette

    @Binding var accent: Accent
    @Binding var inbox: InboxArrangement
    @Binding var appIcon: AppIconChoice
    let appIconIsSupported: Bool
    let tagCount: Int
    @Binding var showsAvatars: Bool

    var body: some View {
        List {
            // COPY BEGIN fce672ac [NEEDS HUMAN REVIEW]
            SettingsHeaderCard(
                icon: "paintpalette.fill",
                title: Text("Appearance", bundle: .module),
                paragraph: Text(
                    "How the app looks on this device. Color, the icon and where conversations are filed are yours alone; nobody else sees a choice you make here.",
                    bundle: .module))
            // COPY END fce672ac

            // COPY BEGIN 25eed54c [NEEDS HUMAN REVIEW]
            Section {
                NavigationLink {
                    AccentPickerView(accent: $accent)
                } label: {
                    SettingsRow(
                        icon: "circle.lefthalf.filled",
                        title: Text("Color", bundle: .module),
                        detail: Text(accent.displayName),
                        swatch: true)
                }
                NavigationLink {
                    AppIconPickerView(choice: $appIcon, isSupported: appIconIsSupported)
                } label: {
                    SettingsRow(
                        icon: "app.badge.fill",
                        title: Text("App icon", bundle: .module),
                        detail: Text(appIcon.displayName))
                }
                NavigationLink {
                    InboxArrangementView(arrangement: $inbox)
                } label: {
                    SettingsRow(
                        icon: "tray.2.fill",
                        title: Text("Inbox", bundle: .module),
                        detail: Text(inbox.shortTitle, bundle: .module))
                }
                SettingsRow(
                    icon: "tag.fill",
                    title: Text("Tags", bundle: .module),
                    detail: Text("\(tagCount)", bundle: .module))
            }
            .groupedRowSurface()
            // COPY END 25eed54c

            // COPY BEGIN 98ee174f [NEEDS HUMAN REVIEW]
            Section {
                SettingsToggle(
                    icon: "person.crop.circle.fill",
                    title: Text("Pictures in conversations", bundle: .module), isOn: $showsAvatars)
            } footer: {
                Text(
                    "Turning pictures off gives conversations their full width. Outposts keep theirs — a post is by somebody, and the face is part of reading it.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END 98ee174f
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN 5d404f69 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Appearance", bundle: .module))
        // COPY END 5d404f69
        .toolbarTitleDisplayMode(.inline)
    }
}
