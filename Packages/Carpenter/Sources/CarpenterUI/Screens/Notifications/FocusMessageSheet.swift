import CarpenterKit
import SwiftUI

struct FocusMessageSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @Binding var focus: FocusSharing
    @FocusState private var writing: Bool

    @State private var draft: String

    init(focus: Binding<FocusSharing>) {
        _focus = focus
        _draft = State(initialValue: focus.wrappedValue.customMessage)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        IconTile("moon.fill", fill: palette.tileFill(.feature))
                        TextField(text: $draft) {
                            Text("Do Not Disturb", bundle: .module)
                        }
                        .textFieldStyle(.plain)
                        .foregroundStyle(palette.primaryText)
                        .focused($writing)
                        .submitLabel(.done)
                        .onSubmit {
                            commit()
                            dismiss()
                        }
                        .onChange(of: draft) { _, typed in
                            if typed.count > FocusStatusBody.messageLimit {
                                draft = String(typed.prefix(FocusStatusBody.messageLimit))
                            }
                        }
                    }
                } header: {
                    Text("What it says", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "\(draft.count) of \(FocusStatusBody.messageLimit). The people you write to see this while you have a Focus on, where you share that. Empty is the plain Do Not Disturb.",
                        bundle: .module)
                }
                .groupedRowSurface()
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(palette.background)
            .navigationTitle(Text("Do Not Disturb", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .task { writing = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        commit()
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                }
            }
        }
    }

    private func commit() {
        let cut = String(
            draft.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(FocusStatusBody.messageLimit))
        var wanted = focus
        wanted.customMessage = cut
        wanted.usesCustomMessage = !cut.isEmpty
        guard wanted != focus else { return }
        focus = wanted
    }
}

#if DEBUG
    #Preview("Changing the Do Not Disturb line") {
        FocusMessageSheet(
            focus: .constant(FocusSharing(usesCustomMessage: true, customMessage: "Back this evening")))
            .themed(.default)
    }
#endif
