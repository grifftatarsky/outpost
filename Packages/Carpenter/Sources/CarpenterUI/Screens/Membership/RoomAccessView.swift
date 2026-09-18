import CarpenterKit
import SwiftUI

public struct RoomAccessView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let roomName: String
    private let members: [Member]
    private let access: RoomAccess
    private let onChange: (RoomAccess) async -> Void

    @State private var count: Int
    @State private var approver: ParticipantID?

    public init(
        roomName: String,
        members: [Member],
        access: RoomAccess,
        onChange: @escaping (RoomAccess) async -> Void
    ) {
        self.roomName = roomName
        self.members = members
        self.access = access
        self.onChange = onChange

        if case .atLeast(let existing) = access {
            _count = State(initialValue: existing)
        } else {
            _count = State(initialValue: 2)
        }
        if case .member(let who) = access {
            _approver = State(initialValue: who)
        } else {
            _approver = State(initialValue: members.first?.id)
        }
    }

    public var body: some View {
        NavigationStack {
            SettingsPage {
                Section {
                    option(
                        .open,
                        title: Text("Anyone invited", bundle: .module),
                        detail: Text("An invitation is enough. Nobody is asked.", bundle: .module)
                    )
                    option(
                        .founder,
                        title: Text("You approve", bundle: .module),
                        detail: Text("You decide on everyone who is invited.", bundle: .module)
                    )
                    option(
                        .anyMember,
                        title: Text("Any member approves", bundle: .module),
                        detail: Text("One person already here has to agree.", bundle: .module)
                    )
                    option(
                        .atLeast(count),
                        title: Text("Several members approve", bundle: .module),
                        detail: Text("^[\(count) member](inflect: true) have to agree.", bundle: .module)
                    )
                    option(
                        .unanimous,
                        title: Text("Everyone approves", bundle: .module),
                        detail: Text(
                            "Everybody already here has to agree, and one refusal is enough to keep someone out.",
                            bundle: .module)
                    )
                    if let approver {
                        option(
                            .member(approver),
                            title: Text("One person decides", bundle: .module),
                            detail: Text("You choose who.", bundle: .module)
                        )
                    }
                } header: {
                    Text(
                        "However you set this, nobody can join without an invitation from someone already here — signed, addressed to them alone, and good only until it runs out. This chooses who else has to agree.",
                        bundle: .module
                    )
                    .textCase(nil)
                    .font(CarpenterFont.footnote)
                }
                .groupedRowSurface()

                if case .atLeast = access {
                    Section {
                        Stepper(value: $count, in: 2...max(2, members.count)) {
                            Text(
                                "^[\(count) member](inflect: true) have to agree", bundle: .module
                            )
                            .foregroundStyle(palette.primaryText)
                        }
                        .onChange(of: count) { _, updated in
                            Task { await onChange(.atLeast(updated)) }
                        }
                    }
                    .groupedRowSurface()
                }

                if case .member = access {
                    Section {
                        ForEach(members) { member in
                            Button {
                                approver = member.id
                                Task { await onChange(.member(member.id)) }
                            } label: {
                                HStack {
                                    Text(member.displayName)
                                        .foregroundStyle(palette.primaryText)
                                    Spacer(minLength: 0)
                                    if approver == member.id {
                                        Image(systemName: "checkmark")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(palette.accentColor)
                                    }
                                }
                            }
                            .accessibilityAddTraits(
                                approver == member.id ? [.isSelected] : [])
                        }
                    }
                    .groupedRowSurface()
                }
            }
            .listSurfaceHidden()
            .pageBackground()
            .navigationTitle(Text("Who gets in", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
        }
    }

    private func option(
        _ candidate: RoomAccess, title: Text, detail: Text
    ) -> some View {
        ChoiceRow(title: title, detail: detail, isSelected: matches(candidate)) {
            Task { await onChange(candidate) }
        }
    }

    private func matches(_ candidate: RoomAccess) -> Bool {
        switch (candidate, access) {
        case (.open, .open), (.founder, .founder), (.anyMember, .anyMember),
            (.unanimous, .unanimous):
            return true
        case (.atLeast, .atLeast), (.member, .member):
            return true
        default:
            return false
        }
    }
}

#if DEBUG
    private struct RoomAccessPreview: View {
        @State private var access: RoomAccess

        init(_ access: RoomAccess) {
            _access = State(initialValue: access)
        }

        var body: some View {
            RoomAccessView(
                roomName: "Hangar 7",
                members: [
                    Member(id: ParticipantID(rawValue: Data(repeating: 1, count: 32)), displayName: "Cassilda"),
                    Member(id: ParticipantID(rawValue: Data(repeating: 2, count: 32)), displayName: "Camilla"),
                ],
                access: access,
                onChange: { access = $0 }
            )
        }
    }

    #Preview("Who gets in — dark") {
        RoomAccessPreview(.open).themed(.default).preferredColorScheme(.dark)
    }

    #Preview("Who gets in — light") {
        RoomAccessPreview(.unanimous).themed(.default).preferredColorScheme(.light)
    }

    #Preview("Who gets in — several") {
        RoomAccessPreview(.atLeast(2)).themed(.default).preferredColorScheme(.dark)
    }
#endif
