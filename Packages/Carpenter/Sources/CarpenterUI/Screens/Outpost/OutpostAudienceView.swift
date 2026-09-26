import CarpenterKit
import SwiftUI

public struct OutpostAudience: Sendable {
    public var people: [Member]
    public var access: OutpostAccess
    public var keyTurnPending: Bool
    public var allow: @Sendable (ParticipantID, Bool) async -> String?
    public var revoke: @Sendable (ParticipantID) async -> String?

    public init(
        people: [Member] = [],
        access: OutpostAccess = OutpostAccess(),
        keyTurnPending: Bool = false,
        allow: @escaping @Sendable (ParticipantID, Bool) async -> String? = { _, _ in nil },
        revoke: @escaping @Sendable (ParticipantID) async -> String? = { _ in nil }
    ) {
        self.people = people
        self.access = access
        self.keyTurnPending = keyTurnPending
        self.allow = allow
        self.revoke = revoke
    }

    public var count: Int { access.audience(at: .now).count }
}

public struct OutpostAudienceView: View {
    @Environment(\.palette) private var palette

    private let people: [Member]
    private let access: OutpostAccess
    private let keyTurnPending: Bool
    private let onAllow: (ParticipantID, Bool) async -> String?
    private let onRevoke: (ParticipantID) async -> String?

    @State private var deciding: OutpostAccessSubject?
    @State private var problem: String?

    public init(
        people: [Member],
        access: OutpostAccess,
        keyTurnPending: Bool = false,
        onAllow: @escaping (ParticipantID, Bool) async -> String? = { _, _ in nil },
        onRevoke: @escaping (ParticipantID) async -> String? = { _ in nil }
    ) {
        self.people = people
        self.access = access
        self.keyTurnPending = keyTurnPending
        self.onAllow = onAllow
        self.onRevoke = onRevoke
    }

    private var allowed: [Member] {
        people.filter { access.grant(for: $0.id)?.isAllowed == true }
            .sorted { $0.displayName < $1.displayName }
    }

    private var undecided: [Member] {
        people.filter { access.grant(for: $0.id)?.isAllowed != true }
            .sorted { $0.displayName < $1.displayName }
    }

    public var body: some View {
        List {
            // COPY BEGIN 1c5b22d8 [NEEDS HUMAN REVIEW]
            SettingsHeaderCard(
                icon: "person.2.badge.key.fill",
                title: Text("Who sees your Outpost", bundle: .module),
                paragraph: Text(
                    "Nobody, until you say so. Being in a room together is not an answer to this. Somebody you let in collects your posts onto their own device, and what they have collected stays theirs if you change your mind.",
                    bundle: .module))
            // COPY END 1c5b22d8

            // COPY BEGIN 9d99cca4 [NEEDS HUMAN REVIEW]
            if keyTurnPending {
                Section {
                    Label {
                        Text(
                            "One change has not taken hold yet. Somebody you removed can still read what you post until this device turns the key, which it tries again every time it syncs.",
                            bundle: .module)
                            .font(CarpenterFont.rowDetail)
                    } icon: {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(palette.destructive)
                    }
                }
                .groupedRowSurface()
            }
            // COPY END 9d99cca4

            if !undecided.isEmpty {
                // COPY BEGIN fb59ecd9 [NEEDS HUMAN REVIEW]
                Section {
                    ForEach(undecided) { person in
                        Button { deciding = subject(person) } label: {
                            PersonRow(
                                name: person.displayName, initials: person.initials, id: person.id,
                                detail: detail(for: person))
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("You have not decided", bundle: .module).sectionHeading()
                }
                .groupedRowSurface()
                // COPY END fb59ecd9
            }

            if allowed.isEmpty {
                // COPY BEGIN 661a8d61 [NEEDS HUMAN REVIEW]
                Section {
                    Text("Nobody can see your Outpost.", bundle: .module)
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.secondaryText)
                }
                .groupedRowSurface()
            } else {
                Section {
                    ForEach(allowed) { person in
                        PersonRow(
                            name: person.displayName, initials: person.initials, id: person.id,
                            detail: detail(for: person)
                        ) {
                            Button { deciding = subject(person) } label: {
                                Text("Change", bundle: .module)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Can see it", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "Removing somebody stops them collecting anything new. It cannot take back what they already have — no app can reach into somebody else's device, and this one does not pretend to.",
                        bundle: .module)
                // COPY END 661a8d61
                }
                .groupedRowSurface()
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN 4d730a02 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Who sees it", bundle: .module))
        // COPY END 4d730a02
        .toolbarTitleDisplayMode(.inline)
        .outpostAccessSheet(deciding: $deciding) { person, choice in
            switch choice {
            case .fromNow: return await onAllow(person, false)
            case .everything: return await onAllow(person, true)
            case .no: return await onRevoke(person)
            }
        }
        // COPY BEGIN c5168cda [NEEDS HUMAN REVIEW]
        .alert(
            Text("That did not go through", bundle: .module),
            isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
        ) {
            Button { problem = nil } label: { Text("OK", bundle: .module) }
        } message: {
            Text(verbatim: problem ?? "")
        }
        // COPY END c5168cda
    }

    private func detail(for person: Member) -> Text {
        Text(verbatim: AccessWindowsCopy.summary(for: access.grant(for: person.id)?.windows ?? []))
    }

    private func subject(_ person: Member) -> OutpostAccessSubject {
        OutpostAccessSubject(person: person, grant: access.grant(for: person.id))
    }
}

#if DEBUG
    #Preview("Who sees your Outpost") {
        var access = OutpostAccess()
        access.allow(
            Fixtures.hastur.id,
            stamp: OrganisationStamp(at: .distantPast, device: DeviceID(rawValue: Data([1]))))
        return NavigationStack {
            OutpostAudienceView(
                people: [Fixtures.hastur, Fixtures.camilla], access: access)
        }
        .themed(.default)
    }
#endif
