#if DEBUG

    import CarpenterKit
    import SwiftUI

    struct AddTestProfileView: View {
        @Environment(\.palette) private var palette
        @Environment(\.dismiss) private var dismiss

        let control: TestProfilesControl

        @State private var name = ""
        @State private var address = ""
        @State private var problem: TestProfileProblem?
        @FocusState private var naming: Bool

        private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

        private var server: URL? {
            let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            if text.hasPrefix("/") { return URL(fileURLWithPath: text, isDirectory: true) }
            guard let url = URL(string: text), url.scheme != nil else { return nil }
            return url
        }

        private var ready: Bool { !trimmedName.isEmpty && server != nil }

        var body: some View {
            List {
                // COPY BEGIN 66c065c9 [NEEDS HUMAN REVIEW]
                Section {
                    TextField(text: $name) { Text("Name", bundle: .module) }
                        .focused($naming)
                        .submitLabel(.next)
                } header: {
                    Text("Profile", bundle: .module).sectionHeading()
                } footer: {
                    Text("Only you see this name. It tells your profiles apart.", bundle: .module)
                }
                .groupedRowSurface()
                // COPY END 66c065c9

                // COPY BEGIN 7a5366c7 [NEEDS HUMAN REVIEW]
                Section {
                    TextField(text: $address) { Text("file:///path/to/mailbox", bundle: .module) }
                        #if !os(macOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                        .onSubmit(add)
                } header: {
                    Text("Mailbox", bundle: .module).sectionHeading()
                } footer: {
                    if let problem {
                        TestProfileProblemText(problem: problem)
                            .foregroundStyle(palette.destructive)
                    } else {
                        Text(
                            "In this build a mailbox is a directory every device in the test can reach, such as a folder shared by simulators on one Mac. HTTPS servers are not built yet.",
                            bundle: .module)
                    }
                }
                .groupedRowSurface()
                // COPY END 7a5366c7
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(palette.background)
            // COPY BEGIN 7d9a26ed [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("New test profile", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: add) { Text("Add", bundle: .module) }
                        .disabled(!ready)
                }
            }
            // COPY END 7d9a26ed
            .task { naming = true }
        }

        private func add() {
            guard ready, let server else { return }
            problem = control.add(TestProfile(name: trimmedName, server: server))
            if problem == nil { dismiss() }
        }
    }

    struct TestProfileProblemText: View {
        let problem: TestProfileProblem

        var body: some View {
            // COPY BEGIN 10729dc1 [NEEDS HUMAN REVIEW]
            switch problem {
            case .serverNotSupported:
                Text("This build only reaches a mailbox at a file:// address. HTTPS servers are not built yet.", bundle: .module)
            case .serverUnreachable:
                Text("That mailbox could not be opened. Check the directory exists and this device can write to it.", bundle: .module)
            case .listNotSaved:
                Text("The list of test profiles could not be saved, so nothing changed.", bundle: .module)
            }
            // COPY END 10729dc1
        }
    }

#endif
