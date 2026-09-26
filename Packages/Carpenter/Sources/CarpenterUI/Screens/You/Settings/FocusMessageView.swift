import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

struct FocusMessageView: View {
    @Environment(\.palette) private var palette

    @Binding var focus: FocusSharing

    @State private var draft: String

    init(focus: Binding<FocusSharing>) {
        _focus = focus
        _draft = State(initialValue: focus.wrappedValue.customMessage)
    }

    private var shown: String {
        focus.usesCustomMessage && !draft.isEmpty ? draft : ""
    }

    private func commit() {
        let cut = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(FocusStatusBody.messageLimit))
        if focus.customMessage != cut { focus.customMessage = cut }
    }

    var body: some View {
        List {
            // COPY BEGIN bfcd4dd9 [NEEDS HUMAN REVIEW]
            SettingsHeaderCard(
                icon: "moon.fill",
                title: Text("Do Not Disturb message", bundle: .module),
                paragraph: Text(
                    "What the people you write to see over the field while you have a Focus on, where you share that. The stock line, or a line of your own.",
                    bundle: .module))
            // COPY END bfcd4dd9

            // COPY BEGIN 6248d976 [NEEDS HUMAN REVIEW]
            Section {
                HStack(spacing: 6) {
                    Image(systemName: "moon.fill")
                    (shown.isEmpty ? Text("Do Not Disturb", bundle: .module) : Text(verbatim: shown))
                        .lineLimit(1)
                }
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .padding(.vertical, 4)
            } header: {
                Text("As they see it", bundle: .module).sectionHeading()
            }
            .groupedRowSurface()
            // COPY END 6248d976

            Section {
                // COPY BEGIN 9aecc1e7 [NEEDS HUMAN REVIEW]
                SettingsToggle(
                    icon: "text.bubble.fill", title: Text("Use custom message", bundle: .module),
                    isOn: $focus.usesCustomMessage)
                // COPY END 9aecc1e7
                if focus.usesCustomMessage {
                    HStack(spacing: 12) {
                        IconTile("pencil", fill: palette.tileFill(.feature))
                        // COPY BEGIN b7d10788 [NEEDS HUMAN REVIEW]
                        TextField(text: $draft) {
                            Text("Back this evening", bundle: .module)
                        }
                        .textFieldStyle(.plain)
                        .foregroundStyle(palette.primaryText)
                        .submitLabel(.done)
                        .onSubmit(commit)
                        .onChange(of: draft) { _, value in
                            if value.count > FocusStatusBody.messageLimit {
                                draft = String(value.prefix(FocusStatusBody.messageLimit))
                            }
                        }
                        // COPY END b7d10788
                    }
                }
            } footer: {
                // COPY BEGIN 142bd793 [NEEDS HUMAN REVIEW]
                if focus.usesCustomMessage {
                    Text("\(draft.count) of \(FocusStatusBody.messageLimit)", bundle: .module)
                }
                // COPY END 142bd793
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(palette.background)
        // COPY BEGIN f68e8cf1 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Do Not Disturb", bundle: .module))
        // COPY END f68e8cf1
        .toolbarTitleDisplayMode(.inline)
        .onDisappear(perform: commit)
    }
}
