import SwiftUI

#if DEBUG

struct ContactSpaceTestView: View {
    @Environment(\.palette) private var palette
    let run: @MainActor @Sendable (ContactSpaceStep) async -> [String]

    @State private var lines: [String] = []
    @State private var running: ContactSpaceStep?
    @State private var finished: [ContactSpaceStep: Bool] = [:]

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
            running = step
            lines = []
            Task {
                lines = await run(step)
                finished[step] = !(lines.first?.hasPrefix("Failed") ?? true)
                running = nil
            }
        } label: {
            HStack {
                SettingsRow(icon: icon, title: title)
                if running == step {
                    ProgressView()
                } else if let ok = finished[step] {
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(ok ? palette.accentColor : palette.destructive)
                }
            }
        }
        .disabled(running != nil)
    }
}

#endif
