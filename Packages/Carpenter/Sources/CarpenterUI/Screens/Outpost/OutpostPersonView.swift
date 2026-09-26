import CarpenterKit
import SwiftUI

public struct OutpostPersonView: View {
    @Environment(\.palette) private var palette

    private let access: ReciprocalAccess
    private let isNotified: Bool
    private let isBlocked: Bool
    private let onChangeAccess: (() -> Void)?
    private let onSetNotified: (Bool) async -> Void
    private let onBlock: () async -> Void
    private let onUnblock: () async -> Void

    @State private var confirmingBlock = false

    public init(
        access: ReciprocalAccess,
        isNotified: Bool = false,
        isBlocked: Bool = false,
        onChangeAccess: (() -> Void)? = nil,
        onSetNotified: @escaping (Bool) async -> Void = { _ in },
        onBlock: @escaping () async -> Void = {},
        onUnblock: @escaping () async -> Void = {}
    ) {
        self.access = access
        self.isNotified = isNotified
        self.isBlocked = isBlocked
        self.onChangeAccess = onChangeAccess
        self.onSetNotified = onSetNotified
        self.onBlock = onBlock
        self.onUnblock = onUnblock
    }

    public var body: some View {
        List {
            // COPY BEGIN 9371b17f [NEEDS HUMAN REVIEW]
            direction(
                title: Text("You can read", bundle: .module),
                windows: access.youCanRead,
                footer: Text(
                    "Only they can change this. What they let you read is their decision, and there is no control here for it.",
                    bundle: .module))
            // COPY END 9371b17f

            Section {
                ForEach(Array(access.theyCanRead.enumerated()), id: \.offset) { _, window in
                    Text(verbatim: AccessWindowsCopy.line(for: window))
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)
                }
                // COPY BEGIN 89928b62 [NEEDS HUMAN REVIEW]
                if access.theyCanRead.isEmpty {
                    Text("Nothing", bundle: .module)
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)
                }
                if let onChangeAccess {
                    Button(action: onChangeAccess) {
                        Text("Change what they can read", bundle: .module)
                    }
                }
            } header: {
                Text("They can read", bundle: .module).sectionHeading()
                // COPY END 89928b62
            }
            .groupedRowSurface()

            if !access.sharedRooms.isEmpty {
                // COPY BEGIN 2a055b0c [NEEDS HUMAN REVIEW]
                Section {
                    ForEach(access.sharedRooms, id: \.self) { room in
                        Text(verbatim: room)
                            .font(CarpenterFont.rowTitle)
                            .foregroundStyle(palette.primaryText)
                    }
                } header: {
                    Text("Rooms you are both in", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "Being in a room together grants nothing either way. It is only how you know each other.",
                        bundle: .module)
                }
                .groupedRowSurface()
                // COPY END 2a055b0c
            }

            // COPY BEGIN 61dd130b [NEEDS HUMAN REVIEW]
            Section {
                Toggle(isOn: notifying) {
                    Text("Tell me when they post", bundle: .module)
                }
            } footer: {
                Text(
                    "They are told you asked, the way anybody knows who follows them. Nobody else is.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END 61dd130b

            Section {
                // COPY BEGIN fab27b68 [NEEDS HUMAN REVIEW]
                if isBlocked {
                    Button { Task { await onUnblock() } } label: {
                        Text("Unblock", bundle: .module)
                    }
                } else {
                    Button(role: .destructive) { confirmingBlock = true } label: {
                        Text("Block", bundle: .module)
                    }
                    .tint(palette.destructive)
                }
            } footer: {
                Text(
                    "Blocking hides everything they write, everywhere, on your devices only. They are not told.",
                    bundle: .module)
                // COPY END fab27b68
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(Text(verbatim: access.person.displayName))
        .toolbarTitleDisplayMode(.inline)
        // COPY BEGIN 2cd8cf30 [NEEDS HUMAN REVIEW]
        .alert(
            Text("Block them?", bundle: .module), isPresented: $confirmingBlock
        ) {
            Button(role: .destructive) { Task { await onBlock() } } label: {
                Text("Block", bundle: .module)
            }
            Button(role: .cancel) { confirmingBlock = false } label: {
                Text("Cancel", bundle: .module)
            }
        } message: {
            Text(
                "\(access.person.displayName) stops being drawn anywhere on your devices. They are not told, and nothing about what they can read of yours changes — that is the setting above.",
                bundle: .module)
        }
        // COPY END 2cd8cf30
    }

    private var notifying: Binding<Bool> {
        Binding(get: { isNotified }, set: { wanted in Task { await onSetNotified(wanted) } })
    }

    private func direction(
        title: Text, windows: [AccessWindow], footer: Text
    ) -> some View {
        Section {
            // COPY BEGIN e6512d51 [NEEDS HUMAN REVIEW]
            if windows.isEmpty {
                Text("Nothing", bundle: .module)
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
            } else {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    Text(verbatim: AccessWindowsCopy.line(for: window))
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)
                }
            }
            // COPY END e6512d51
        } header: {
            title.sectionHeading()
        } footer: {
            footer
        }
        .groupedRowSurface()
    }
}

#if DEBUG
    #Preview("One person's access") {
        NavigationStack {
            OutpostPersonView(
                access: ReciprocalAccess(
                    person: Fixtures.camilla,
                    sharedRooms: ["The Gazette", "Zeppelin Enthusiasts"],
                    theyGave: OutpostAccess.Grant(),
                    youGave: OutpostAccess.Grant(windows: [
                        AccessWindow(
                            from: Date(timeIntervalSince1970: 1_757_000_000),
                            until: Date(timeIntervalSince1970: 1_775_260_800)),
                        AccessWindow(from: Date(timeIntervalSince1970: 1_779_000_000)),
                    ])),
                isNotified: true,
                onChangeAccess: {})
        }
        .themed(.default)
    }
#endif
