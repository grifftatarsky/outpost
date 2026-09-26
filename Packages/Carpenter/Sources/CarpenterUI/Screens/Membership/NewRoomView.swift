import CarpenterKit
import SwiftUI

struct NewRoomView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var naming: Bool

    @State private var name = ""
    @State private var created = 0
    @State private var isAdvanced = false
    @State private var access: RoomAccess = .open
    @State private var approvals = 2
    @State private var explaining: RoomAccess?
    @State private var detent: PresentationDetent = .medium
    @State private var picking = false

    @Bindable var preferences: RoomsListPreferences
    let connections: [Connection]
    let onCreate: (String, RoomAccess, Set<ParticipantID>) async -> Void

    private static let mostApprovalsAtCreation = 5

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                // COPY BEGIN eb5bc607 [NEEDS HUMAN REVIEW]
                Section {
                    TextField(text: $name) { Text("Name", bundle: .module) }
                        .focused($naming)
                        .submitLabel(.done)
                        .onSubmit(create)
                } footer: {
                    Text("Only you are in it until you invite someone.", bundle: .module)
                }
                .groupedRowSurface()
                // COPY END eb5bc607

                // COPY BEGIN 8dda4bc3 [NEEDS HUMAN REVIEW]
                Section {
                    Toggle(isOn: $isAdvanced) {
                        Text("Advanced setup", bundle: .module)
                            .foregroundStyle(palette.primaryText)
                    }
                } footer: {
                    Text("Choose who has to agree before somebody new can join.", bundle: .module)
                }
                .groupedRowSurface()
                // COPY END 8dda4bc3

                // COPY BEGIN 0ec0e0cb [NEEDS HUMAN REVIEW]
                Section {
                    Toggle(isOn: $preferences.bringsPeopleIn) {
                        Text("Bring people in", bundle: .module)
                            .foregroundStyle(palette.primaryText)
                    }
                    .disabled(connections.isEmpty)
                } footer: {
                    connections.isEmpty
                        ? Text(
                            "Once you share a room with somebody, you can bring them straight into a new one.",
                            bundle: .module)
                        : Text("Choose who to invite after naming the room.", bundle: .module)
                }
                .groupedRowSurface()
                // COPY END 0ec0e0cb

                if isAdvanced {
                    policySection
                    if case .atLeast = access { approvalsSection }
                }
            }
            .animation(reduceMotion ? nil : .default, value: isAdvanced)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(palette.background)
            // COPY BEGIN a861d074 [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("New room", bundle: .module))
            // COPY END a861d074
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $picking) {
                PeoplePickerView(connections: connections) { chosen in
                    finish(inviting: chosen)
                }
            }
            // COPY BEGIN 2e055b39 [NEEDS HUMAN REVIEW]
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: create) { Text("Create", bundle: .module) }
                        .disabled(trimmed.isEmpty)
                }
            }
            // COPY END 2e055b39
            .task { naming = true }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .onChange(of: isAdvanced) { _, advanced in detent = advanced ? .large : .medium }
        .onChange(of: picking) { _, choosing in if choosing { detent = .large } }
        .haptic(.commit, trigger: created)
    }

    private var policySection: some View {
        Section {
            // COPY BEGIN bca2f823 [NEEDS HUMAN REVIEW]
            option(
                .open,
                title: Text("Anyone invited", bundle: .module),
                detail: Text("An invitation is enough. Nobody is asked.", bundle: .module),
                explanation: Text(
                    "Whoever invites somebody decides on their own. This is how most rooms work, and it is what happens if you change nothing here.",
                    bundle: .module)
            )
            option(
                .founder,
                title: Text("You approve", bundle: .module),
                detail: Text("You decide on everyone who is invited.", bundle: .module),
                explanation: Text(
                    "Anybody here can invite somebody, and nobody joins until you have agreed. If you stop using this room, nobody else can approve in your place.",
                    bundle: .module)
            )
            option(
                .anyMember,
                title: Text("Any member approves", bundle: .module),
                detail: Text("One person already here has to agree.", bundle: .module),
                explanation: Text(
                    "Somebody other than whoever invited them has to agree. One person is enough, and it can be anybody already in the room.",
                    bundle: .module)
            )
            option(
                .atLeast(approvals),
                title: Text("Several members approve", bundle: .module),
                detail: Text("^[\(approvals) member](inflect: true) have to agree.", bundle: .module),
                explanation: Text(
                    "You are choosing this before anybody is here, so it never asks for more approvals than there are members: a room set to four is everybody until it has four, then it is four. You can change it later.",
                    bundle: .module)
            )
            option(
                .unanimous,
                title: Text("Everyone approves", bundle: .module),
                detail: Text("Everybody here has to agree.", bundle: .module),
                explanation: Text(
                    "Every member has to agree, and one refusal is enough to keep somebody out. In a busy room this can mean nobody joins for a while.",
                    bundle: .module)
            )
            // COPY END bca2f823
        } header: {
            // COPY BEGIN 819f1ebd [NEEDS HUMAN REVIEW]
            Text(
                "Nobody can join without an invitation from someone already here, whatever you choose. This is who else has to agree.",
                bundle: .module
            )
            .textCase(nil)
            .font(CarpenterFont.footnote)
            // COPY END 819f1ebd
        }
        .groupedRowSurface()
    }

    // COPY BEGIN 41bb7db6 [NEEDS HUMAN REVIEW]
    private var approvalsSection: some View {
        Section {
            Stepper(value: $approvals, in: 2...Self.mostApprovalsAtCreation) {
                Text("^[\(approvals) member](inflect: true) have to agree", bundle: .module)
                    .foregroundStyle(palette.primaryText)
            }
            .onChange(of: approvals) { _, updated in access = .atLeast(updated) }
        } footer: {
            Text(
                "Never more than there are members: this is everybody until the room is that big.",
                bundle: .module)
        }
        .groupedRowSurface()
    }
    // COPY END 41bb7db6

    private func option(
        _ value: RoomAccess, title: Text, detail: Text, explanation: Text
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ChoiceRow(
                    title: title,
                    detail: detail,
                    isSelected: isSameKind(access, value),
                    action: { access = value }
                )
                // COPY BEGIN 3d090a37 [NEEDS HUMAN REVIEW]
                Button {
                    explaining = isExplaining(value) ? nil : value
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(palette.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("What this means", bundle: .module))
                // COPY END 3d090a37
            }
            if isExplaining(value) {
                explanation
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func isExplaining(_ value: RoomAccess) -> Bool {
        explaining.map { isSameKind($0, value) } ?? false
    }

    private func isSameKind(_ lhs: RoomAccess, _ rhs: RoomAccess) -> Bool {
        switch (lhs, rhs) {
        case (.open, .open), (.founder, .founder), (.anyMember, .anyMember),
            (.unanimous, .unanimous):
            return true
        case (.atLeast, .atLeast), (.member, .member):
            return true
        default:
            return false
        }
    }

    private func create() {
        guard !trimmed.isEmpty else { return }
        if preferences.bringsPeopleIn && !connections.isEmpty {
            picking = true
        } else {
            finish(inviting: [])
        }
    }

    private func finish(inviting people: Set<ParticipantID>) {
        let outgoing = trimmed
        let chosen = access
        guard !outgoing.isEmpty else { return }
        dismiss()
        created += 1
        Task { await onCreate(outgoing, chosen, people) }
    }
}

#Preview("New room") {
    NewRoomView(preferences: RoomsListPreferences(), connections: []) { _, _, _ in }
        .themed(.default)
}
