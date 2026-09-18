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
            SettingsHeaderCard(
                icon: "moon.fill",
                title: Text("Do Not Disturb message", bundle: .module),
                paragraph: Text(
                    "What the people you write to see over the field while you have a Focus on, where you share that. The stock line, or a line of your own.",
                    bundle: .module))

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

            Section {
                SettingsToggle(
                    icon: "text.bubble.fill", title: Text("Use custom message", bundle: .module),
                    isOn: $focus.usesCustomMessage)
                if focus.usesCustomMessage {
                    HStack(spacing: 12) {
                        IconTile("pencil", fill: palette.tileFill(.feature))
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
                    }
                }
            } footer: {
                if focus.usesCustomMessage {
                    Text("\(draft.count) of \(FocusStatusBody.messageLimit)", bundle: .module)
                }
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(palette.background)
        .navigationTitle(Text("Do Not Disturb", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        .onDisappear(perform: commit)
    }
}
