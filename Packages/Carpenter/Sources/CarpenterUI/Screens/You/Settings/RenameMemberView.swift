import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

struct RenameMemberView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editing: Bool

    @State private var name: String
    @State private var saving = false
    @State private var problem: String?
    let onRename: (String) async -> String?

    init(current: String, onRename: @escaping (String) async -> String?) {
        _name = State(initialValue: current)
        self.onRename = onRename
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            Section {
                TextField(text: $name) { Text("Name", bundle: .module) }
                    .focused($editing)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .onSubmit(save)
            } footer: {
                if let problem {
                    Text(verbatim: problem).foregroundStyle(palette.destructive)
                } else {
                    Text("The initials on your avatar come from this.", bundle: .module)
                }
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(palette.background)
        .navigationTitle(Text("Name", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) { Text("Done", bundle: .module) }
                    .disabled(trimmed.isEmpty || saving)
            }
        }
        .task { editing = true }
    }

    private func save() {
        let outgoing = trimmed
        guard !outgoing.isEmpty, !saving else { return }
        saving = true
        problem = nil
        Task {
            let failure = await onRename(outgoing)
            saving = false
            if let failure {
                problem = failure
            } else {
                dismiss()
            }
        }
    }
}
