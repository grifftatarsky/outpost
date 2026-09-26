import CarpenterKit
import SwiftUI

public struct RestoreFromKeyView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let restore: (String, Bool, Bool) async -> String?

    @State private var key = ""
    @State private var asksPeers = true
    @State private var lostOrStolen: Bool?
    @State private var working = false
    @State private var problem: String?
    @FocusState private var typing: Bool

    public init(restore: @escaping (String, Bool, Bool) async -> String?) {
        self.restore = restore
    }

    private var ready: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !working
            && lostOrStolen != nil
    }

    private func begin() {
        guard ready else { return }
        working = true
        problem = nil
        Task {
            let failure = await restore(key, asksPeers, lostOrStolen == true)
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
                // COPY BEGIN ef3ec642 [NEEDS HUMAN REVIEW]
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
                    // COPY BEGIN 8ac43771 [NEEDS HUMAN REVIEW]
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

                // COPY BEGIN 48aa82d0 [NEEDS HUMAN REVIEW]
                Section {
                    ChoiceRow(
                        title: Text("No", bundle: .module),
                        isSelected: lostOrStolen == false,
                        action: { lostOrStolen = false })
                    ChoiceRow(
                        title: Text("Yes", bundle: .module),
                        isSelected: lostOrStolen == true,
                        action: { lostOrStolen = true })
                } header: {
                    Text("Was a device lost or stolen?", bundle: .module).sectionHeading()
                } footer: {
                    switch lostOrStolen {
                    case true:
                        Text(
                            "Conversations rotate keys, removing the lost or stolen device. Your other devices will need the recovery key.",
                            bundle: .module)
                    case false:
                        Text(
                            "No keys are rotated. A device you no longer have would keep reading — you can still cut one off later under Devices.",
                            bundle: .module)
                    default:
                        Text(
                            "This app cannot tell a new device from a stolen one, so if your device was lost or stolen your conversations will rotate keys.",
                            bundle: .module)
                    }
                }
                .groupedRowSurface()
                // COPY END 48aa82d0

                // COPY BEGIN 7b506c4b [NEEDS HUMAN REVIEW]
                Section {
                    SettingsToggle(
                        icon: "hand.wave.fill",
                        title: Text("Request history backfill", bundle: .module),
                        isOn: $asksPeers)
                } header: {
                    Text("Getting your history back", bundle: .module).sectionHeading()
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

                Section {
                    // COPY BEGIN 38d1c645 [NEEDS HUMAN REVIEW]
                    Label {
                        Text("Your rooms come back as people reach you again", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark").foregroundStyle(palette.accentColor)
                    }
                    Label {
                        Text("What was said comes back only from the people who still hold it", bundle: .module)
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(palette.secondaryText)
                    }
                } header: {
                    Text("What to expect", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "Anybody you talked to who is still on this app can hand your history back. Anything nobody kept is gone.",
                        bundle: .module)
                    // COPY END 38d1c645
                }
                .groupedRowSurface()
            }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // COPY BEGIN ad65cb88 [NEEDS HUMAN REVIEW]
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
            RestoreFromKeyView(restore: { _, _, _ in "That does not look like a recovery key." })
        }
        .themed(.default)
    }
#endif
