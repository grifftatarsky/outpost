import CarpenterKit
import SwiftUI

public struct RestoreFromKeyView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let restore: (String, Bool) async -> String?

    @State private var key = ""
    @State private var asksPeers = true
    @State private var working = false
    @State private var problem: String?
    @FocusState private var typing: Bool

    public init(restore: @escaping (String, Bool) async -> String?) {
        self.restore = restore
    }

    private var ready: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !working
    }

    private func begin() {
        guard ready else { return }
        working = true
        problem = nil
        Task {
            let failure = await restore(key, asksPeers)
            working = false
            if let failure {
                problem = failure
            } else {
                dismiss()
            }
        }
    }

    public var body: some View {
        List {
                // COPY BEGIN ef3ec642 [HUMAN REVIEWED, UNVERIFIED]
                Section {
                    SettingsHeaderCard(
                        icon: "key.horizontal.fill",
                        title: Text("Use your recovery key", bundle: .module),
                        paragraph: Text(
                            "Paste the whole file, header line and all.",
                            bundle: .module))
                }
                .groupedRowSurface()
                // COPY END ef3ec642

                Section {
                    // COPY BEGIN 8ac43771 [HUMAN REVIEWED, UNVERIFIED]
                    TextField(
                        text: $key,
                        prompt: Text(verbatim: "\(RecoveryKey.header)…"),
                        axis: .vertical
                    ) {
                        Text("Recovery key", bundle: .module)
                    }
                    .textFieldStyle(.plain)
                    .font(.footnote.monospaced())
                    .lineLimit(4...10)
                    .codeEntry()
                    .focused($typing)
                    .onAppear { typing = true }
                } header: {
                    Text("The file", bundle: .module).sectionHeading()
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(palette.destructive)
                    } else {
                        Text(
                            "The key is read on device and restored to the iCloud keychain.",
                            bundle: .module)
                    }
                    // COPY END 8ac43771
                }
                .groupedRowSurface()

                // COPY BEGIN 7b506c4b [HUMAN REVIEWED, UNVERIFIED]
                Section {
                    SettingsToggle(
                        icon: "hand.wave.fill",
                        title: Text("Request history backfill", bundle: .module),
                        isOn: $asksPeers)
                } footer: {
                    if asksPeers {
                        Text(
                            "History providers (people you message) will be asked, and configured devices will see you're using a new device.",
                            bundle: .module)
                    } else {
                        Text(
                            "No one will see you have set up a new device, but you cannot obtain any history until you enable this.",
                            bundle: .module)
                    }
                }
                .groupedRowSurface()
                // COPY END 7b506c4b

            }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // COPY BEGIN ad65cb88 [HUMAN REVIEWED, UNVERIFIED]
        .safeAreaInset(edge: .bottom) {
            Button(action: begin) {
                Text("Restore this device", bundle: .module).primaryAction()
            }
            .prominentActionButton()
            .disabled(!ready)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(palette.background)
        .navigationTitle(Text("Recovery Key", bundle: .module))
        // COPY END ad65cb88
        .toolbarTitleDisplayMode(.inline)
    }
}

#if DEBUG
    #Preview("Restore from a key") {
        NavigationStack {
            RestoreFromKeyView(restore: { _, _ in "That does not look like a recovery key." })
        }
        .themed(.default)
    }
#endif
