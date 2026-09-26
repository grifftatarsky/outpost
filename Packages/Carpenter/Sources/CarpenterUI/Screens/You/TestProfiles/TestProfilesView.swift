#if DEBUG

    import CarpenterKit
    import SwiftUI

    struct TestProfilesView: View {
        @Environment(\.palette) private var palette

        let control: TestProfilesControl

        @State private var adding = false
        @State private var deleting: TestProfile?
        @State private var working = false
        @State private var problem: TestProfileProblem?

        var body: some View {
            List {
                // COPY BEGIN 0b6f67d2 [NEEDS HUMAN REVIEW]
                SettingsHeaderCard(
                    icon: "testtube.2", tone: .device,
                    title: Text("Test profiles", bundle: .module),
                    paragraph: Text(
                        "A test profile runs this app against a mailbox you host instead of CloudKit. Each one is a world of its own, with its own identity, conversations and contacts, and only the world in use is shown. While a profile is on, CloudKit messaging is paused: what people send you over iCloud waits, and arrives when you switch back. Invitations can run out while you are away.",
                        bundle: .module))
                // COPY END 0b6f67d2

                Section {
                    // COPY BEGIN 1b5849c4 [NEEDS HUMAN REVIEW]
                    ChoiceRow(
                        title: Text("iCloud", bundle: .module),
                        detail: Text("CloudKit messaging", bundle: .module),
                        isSelected: control.activeID == nil,
                        action: { choose(nil) })
                    // COPY END 1b5849c4
                    ForEach(control.profiles) { profile in
                        ChoiceRow(
                            title: Text(verbatim: profile.name),
                            detail: Text(verbatim: profile.server.isFileURL ? profile.server.path : profile.server.absoluteString),
                            isSelected: control.activeID == profile.id,
                            action: { choose(profile.id) })
                        .swipeActions(edge: .trailing) {
                            if control.activeID != profile.id {
                                Button {
                                    deleting = profile
                                } label: {
                                    // COPY BEGIN fa7f6193 [NEEDS HUMAN REVIEW]
                                    Label {
                                        Text("Delete", bundle: .module)
                                    } icon: {
                                        Image(systemName: "trash")
                                    }
                                    // COPY END fa7f6193
                                }
                                .tint(palette.destructive)
                            }
                        }
                    }
                    .disabled(working)
                    Button {
                        adding = true
                    } label: {
                        // COPY BEGIN 5d8f5aa4 [NEEDS HUMAN REVIEW]
                        SettingsRow(
                            icon: "plus", tone: .feature,
                            title: Text("Add a test profile", bundle: .module))
                        // COPY END 5d8f5aa4
                    }
                    .disabled(working)
                } header: {
                    // COPY BEGIN cf5604ad [NEEDS HUMAN REVIEW]
                    Text("Messaging through", bundle: .module).sectionHeading()
                } footer: {
                    if let problem {
                        TestProfileProblemText(problem: problem)
                            .foregroundStyle(palette.destructive)
                    } else if working {
                        Text("Switching. This closes one world and opens the other.", bundle: .module)
                    } else {
                        Text("Swipe a profile to delete it. The one in use cannot be deleted.", bundle: .module)
                    }
                    // COPY END cf5604ad
                }
                .groupedRowSurface()
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            // COPY BEGIN 1d4a198d [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("Test profiles", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .confirmationDialog(
                Text("Delete \(deleting?.name ?? "")?", bundle: .module),
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible,
                presenting: deleting
            ) { profile in
                Button(role: .destructive) {
                    remove(profile.id)
                } label: {
                    Text("Delete profile", bundle: .module)
                }
            } message: { _ in
                Text(
                    "Its identity, conversations and contacts on this device are deleted. The mailbox it points at is not touched.",
                    bundle: .module)
            }
            // COPY END 1d4a198d
            .sheet(isPresented: $adding) {
                NavigationStack {
                    AddTestProfileView(control: control)
                }
                .themed(palette.accent)
            }
        }

        private func choose(_ id: UUID?) {
            guard !working, id != control.activeID else { return }
            working = true
            problem = nil
            Task {
                problem = if let id { await control.start(id) } else { await control.stop() }
                working = false
            }
        }

        private func remove(_ id: UUID) {
            deleting = nil
            Task { problem = await control.remove(id) }
        }
    }

#endif
