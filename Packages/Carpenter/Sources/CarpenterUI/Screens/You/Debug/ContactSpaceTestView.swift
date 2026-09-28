import SwiftUI

#if DEBUG

struct ContactSpaceTestView: View {
    @Environment(\.palette) private var palette
    let run: @MainActor @Sendable (ContactSpaceStep) async -> [String]

    @State private var lines: [String] = []
    @State private var running = false

    var body: some View {
        List {
            Section {
                step(.join, icon: "person.badge.plus", title: Text("Join the test space", bundle: .module))
                step(.watch, icon: "bell", title: Text("Watch contacts' spaces", bundle: .module))
                step(.check, icon: "list.bullet", title: Text("Check what arrived", bundle: .module))
                step(.remove, icon: "trash", title: Text("Remove the test", bundle: .module))
            }
            .groupedRowSurface()

            if !lines.isEmpty {
                Section {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                            .font(.footnote.monospaced())
                            .foregroundStyle(palette.secondaryText)
                            .textSelection(.enabled)
                    }
                }
                .groupedRowSurface()
            }
        }
        .navigationTitle(Text("Test a contact's space", bundle: .module))
    }

    private func step(_ step: ContactSpaceStep, icon: String, title: Text) -> some View {
        Button {
            running = true
            Task {
                lines = await run(step)
                running = false
            }
        } label: {
            SettingsRow(icon: icon, title: title)
        }
        .disabled(running)
    }
}

#endif
