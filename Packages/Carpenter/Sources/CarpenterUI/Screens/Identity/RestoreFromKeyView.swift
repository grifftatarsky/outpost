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
        SettingsPage {
                Section {
                    SettingsHeaderCard(
                        icon: "key.horizontal.fill",
                        title: Text("Use your recovery key", bundle: .module),
                        paragraph: Text(
                            "Paste the whole file, header line and all. It makes this device you again.",
                            bundle: .module))
                }
                .groupedRowSurface()

                Section {
                    TextField(
                        text: $key,
                        prompt: Text("OUTPOST RECOVERY KEY…", bundle: .module),
                        axis: .vertical
                    ) {
                        Text("Recovery key", bundle: .module)
                    }
                    .textFieldStyle(.plain)
                    .font(.footnote.monospaced())
                    .lineLimit(4...10)
                    .codeEntry()
                    .focused($typing)
                    .returnIsDone($key, focus: $typing)
                    .onAppear { typing = true }
                } header: {
                    Text("The file", bundle: .module).sectionHeading()
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(palette.destructive)
                    } else {
                        Text(
                            "Nothing is sent anywhere. The key is read on this device and put back in your keychain.",
                            bundle: .module)
                    }
                }
                .groupedRowSurface()

                Section {
                    ChoiceRow(
                        title: Text("No — I still have it, or I am adding a device", bundle: .module),
                        isSelected: lostOrStolen == false,
                        action: { lostOrStolen = false })
                    ChoiceRow(
                        title: Text("Yes — a device was lost or stolen", bundle: .module),
                        isSelected: lostOrStolen == true,
                        action: { lostOrStolen = true })
                } header: {
                    Text("What happened", bundle: .module).sectionHeading()
                } footer: {
                    switch lostOrStolen {
                    case true:
                        Text(
                            "Every room turns its key, so the device that is gone stops reading what is said from now on. It cannot be undone, and any other device you still own goes quiet until you restore it too.",
                            bundle: .module)
                    case false:
                        Text(
                            "No keys turn. A device you no longer have would keep reading — you can still cut one off later under Devices.",
                            bundle: .module)
                    default:
                        Text(
                            "This app cannot tell a new device from a stolen one, and the answer decides whether every room turns its key. Nothing is restored until you say which it was.",
                            bundle: .module)
                    }
                }
                .groupedRowSurface()

                Section {
                    SettingsToggle(
                        icon: "hand.wave.fill",
                        title: Text("Ask the people I talk to for what was said", bundle: .module),
                        isOn: $asksPeers)
                } header: {
                    Text("Getting your history back", bundle: .module).sectionHeading()
                } footer: {
                    if asksPeers {
                        Text(
                            "Each of them is asked once for their copy of what was said. Some will be told you set up a new device — that is their setting, not yours. Anything nobody kept is gone.",
                            bundle: .module)
                    } else {
                        Text(
                            "Nobody is asked and nobody is told. Your rooms come back as people reach you again, but they come back empty — and there is no way to ask for the old messages later except by turning this back on.",
                            bundle: .module)
                    }
                }
                .groupedRowSurface()

                Section {
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
                }
                .groupedRowSurface()
            }
        .listSurfaceHidden()
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: begin) {
                Text("Restore this device", bundle: .module).primaryAction()
            }
            .prominentActionButton()
            .disabled(!ready)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .pageBackground()
        .navigationTitle(Text("Recovery key", bundle: .module))
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
