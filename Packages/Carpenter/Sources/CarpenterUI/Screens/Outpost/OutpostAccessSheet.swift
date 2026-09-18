import CarpenterKit
import SwiftUI

public typealias OutpostAccessChoice = OutpostAccess.Choice

public struct OutpostAccessSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let person: Member
    private let grant: OutpostAccess.Grant?
    private let onChoose: (OutpostAccessChoice) async -> String?

    @State private var confirming: OutpostAccessChoice?
    @State private var problem: String?
    @State private var working = false

    public init(
        person: Member,
        grant: OutpostAccess.Grant?,
        onChoose: @escaping (OutpostAccessChoice) async -> String? = { _ in nil }
    ) {
        self.person = person
        self.grant = grant
        self.onChoose = onChoose
    }

    private var standing: OutpostAccess.Standing { OutpostAccess.Standing(grant) }
    private var windows: [AccessWindow] { grant?.windows ?? [] }

    public var body: some View {
        NavigationStack {
            List {
                SettingsHeaderCard(
                    icon: "person.2.badge.key.fill",
                    title: Text(verbatim: person.displayName),
                    paragraph: Text(
                        "Nobody reads your Outpost unless you say so. What somebody can read is a set of periods — each choice below opens one or closes one.",
                        bundle: .module))

                record
                changes
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle(Text("Their access", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
            .disabled(working)
            .alert(
                Text("This cannot be undone", bundle: .module),
                isPresented: Binding(
                    get: { confirming != nil }, set: { if !$0 { confirming = nil } })
            ) {
                Button(role: .destructive) {
                    let choice = confirming
                    confirming = nil
                    if let choice { apply(choice) }
                } label: {
                    Text("Give them everything", bundle: .module)
                }
                Button(role: .cancel) { confirming = nil } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: {
                Text(
                    "\(person.displayName) collects your whole Outpost onto their own device. You can stop them getting anything new, but you cannot take back what they have.",
                    bundle: .module)
            }
            .alert(
                Text("That did not go through", bundle: .module),
                isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
            ) {
                Button { problem = nil } label: { Text("OK", bundle: .module) }
            } message: {
                Text(verbatim: problem ?? "")
            }
        }
    }

    @ViewBuilder private var record: some View {
        Section {
            if windows.isEmpty {
                Text("Nothing. They have never collected a post from here.", bundle: .module)
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.secondaryText)
            } else {
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    HStack(spacing: 12) {
                        Text(verbatim: AccessWindowsCopy.line(for: window))
                            .font(CarpenterFont.rowTitle)
                            .foregroundStyle(palette.primaryText)
                        Spacer(minLength: 0)
                        if window.isOpen {
                            Text("Still collecting", bundle: .module)
                                .font(CarpenterFont.rowDetail)
                                .foregroundStyle(palette.accentColor)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("What they can read", bundle: .module).sectionHeading()
        } footer: {
            if windows.count > 1 {
                Text(
                    "More than one period means they were let in, stopped, and let in again. What falls between is sealed to them.",
                    bundle: .module)
            }
        }
        .groupedRowSurface()
    }

    private var changes: some View {
        Section {
            ForEach(standing.offers, id: \.self) { choice in
                ChoiceRow(
                    title: title(for: choice),
                    detail: consequence(for: choice),
                    isSelected: false,
                    action: {
                        if OutpostAccess.Standing.isFinal(choice) {
                            confirming = choice
                        } else {
                            apply(choice)
                        }
                    })
            }
        } header: {
            Text("Change it", bundle: .module).sectionHeading()
        } footer: {
            footer
        }
        .groupedRowSurface()
    }

    private var footer: Text {
        switch standing {
        case .everything:
            return Text(
                "You have already given them everything, and that cannot be taken back. Stopping ends what they collect from now on.",
                bundle: .module)
        case .none, .from:
            return Text(
                "Giving somebody everything cannot be undone. Everything else here can: a period you close can be opened again, and what falls between stays sealed to them.",
                bundle: .module)
        }
    }

    private func title(for choice: OutpostAccessChoice) -> Text {
        switch choice {
        case .fromNow: return Text("Let them see from now on", bundle: .module)
        case .everything: return Text("Let them see everything", bundle: .module)
        case .no: return Text("Stop them seeing anything new", bundle: .module)
        }
    }

    private func consequence(for choice: OutpostAccessChoice) -> Text {
        switch choice {
        case .fromNow:
            return Text(
                "A new period starts today. Everything you posted before it stays sealed to them.",
                bundle: .module)
        case .everything:
            return Text(
                "They collect every post on this wall, including everything from before you met. This cannot be undone.",
                bundle: .module)
        case .no:
            return Text(
                "Today's period ends. They keep what they have already collected, and nothing you post from now reaches them.",
                bundle: .module)
        }
    }

    private func apply(_ choice: OutpostAccessChoice) {
        working = true
        Task {
            problem = await onChoose(choice)
            working = false
            if problem == nil { dismiss() }
        }
    }
}

#if DEBUG
    #Preview("Their access — a stretch open") {
        OutpostAccessSheet(
            person: Fixtures.camilla,
            grant: OutpostAccess.Grant(windows: [
                AccessWindow(
                    from: Date(timeIntervalSince1970: 1_757_000_000),
                    until: Date(timeIntervalSince1970: 1_775_260_800)),
                AccessWindow(from: Date(timeIntervalSince1970: 1_779_000_000)),
            ]))
            .themed(.default)
    }

    #Preview("Their access — everything") {
        OutpostAccessSheet(person: Fixtures.hastur, grant: OutpostAccess.Grant())
            .themed(.default)
    }

    #Preview("Their access — nothing yet") {
        OutpostAccessSheet(person: Fixtures.hastur, grant: nil)
            .themed(.default)
    }
#endif
