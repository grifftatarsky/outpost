import CarpenterKit
import SwiftUI

public struct InvitedPerson: Identifiable, Hashable, Sendable {
    public let person: Member
    public let phrase: String
    public let expiresAt: Date
    public let hasConfirmed: Bool
    public let isMine: Bool

    public let invitedBy: Member
    public let hasLapsed: Bool
    public let awaitsMyApproval: Bool
    public let agreed: (count: Int, needed: Int)?

    public var id: ParticipantID { person.id }

    public var isIndefinite: Bool { expiresAt >= .distantFuture }

    public init(
        person: Member, phrase: String, expiresAt: Date, hasConfirmed: Bool, isMine: Bool,
        invitedBy: Member, awaitsMyApproval: Bool, agreed: (count: Int, needed: Int)? = nil,
        hasLapsed: Bool = false
    ) {
        self.hasLapsed = hasLapsed
        self.invitedBy = invitedBy
        self.person = person
        self.phrase = phrase
        self.expiresAt = expiresAt
        self.hasConfirmed = hasConfirmed
        self.isMine = isMine
        self.awaitsMyApproval = awaitsMyApproval
        self.agreed = agreed
    }

    public static func == (lhs: InvitedPerson, rhs: InvitedPerson) -> Bool {
        lhs.person == rhs.person && lhs.phrase == rhs.phrase && lhs.expiresAt == rhs.expiresAt
            && lhs.hasConfirmed == rhs.hasConfirmed && lhs.isMine == rhs.isMine
            && lhs.awaitsMyApproval == rhs.awaitsMyApproval
            && lhs.agreed?.count == rhs.agreed?.count && lhs.agreed?.needed == rhs.agreed?.needed
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(person)
        hasher.combine(hasConfirmed)
    }
}

public struct RoomMembersView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let roomName: String
    private let members: [Member]
    private let viewer: ParticipantID?
    private let invited: [InvitedPerson]
    private let onRemove: ((ParticipantID) async -> Void)?
    private let onInvite: (() -> Void)?
    private let onRescind: ((ParticipantID) async -> Void)?
    private let joins: [PendingJoin]
    private let onDecide: ((PendingJoin, Bool) async -> Void)?
    private let onBlock: ((ParticipantID) async -> Void)?
    private let personPage: ((ParticipantID, PersonActions?) -> PersonDetailView)?

    @State private var removing: Member?
    @State private var blocking: Member?
    @State private var rescinding: InvitedPerson?
    @State private var checking: InvitedPerson?
    @State private var rescindingOnceChecked: InvitedPerson?

    public init(
        roomName: String,
        members: [Member],
        invited: [InvitedPerson] = [],
        viewer: ParticipantID? = nil,
        onRemove: ((ParticipantID) async -> Void)? = nil,
        onInvite: (() -> Void)? = nil,
        onBlock: ((ParticipantID) async -> Void)? = nil,
        onRescind: ((ParticipantID) async -> Void)? = nil,
        joins: [PendingJoin] = [],
        onDecide: ((PendingJoin, Bool) async -> Void)? = nil,
        personPage: ((ParticipantID, PersonActions?) -> PersonDetailView)? = nil
    ) {
        self.roomName = roomName
        self.members = members
        self.invited = invited
        self.viewer = viewer
        self.onRemove = onRemove
        self.onInvite = onInvite
        self.onBlock = onBlock
        self.onRescind = onRescind
        self.joins = joins
        self.onDecide = onDecide
        self.personPage = personPage
    }

    public var body: some View {
        List {
            Section {
                ForEach(members) { member in
                    row(member)
                }
            } header: {
                // COPY BEGIN b033f3e8 [NEEDS HUMAN REVIEW]
                Text("^[\(members.count) member](inflect: true)", bundle: .module).sectionHeading()
            } footer: {
                if members.contains(where: { $0.id != viewer }) {
                    switch (onRemove != nil, onBlock != nil) {
                    case (true, true):
                        Text(
                            "Tap somebody to remove them from this room, or to block them everywhere.",
                            bundle: .module)
                    case (true, false):
                        Text("Tap somebody to remove them from this room.", bundle: .module)
                    case (false, true):
                        Text("Tap somebody to block them everywhere.", bundle: .module)
                    case (false, false):
                        EmptyView()
                    }
                // COPY END b033f3e8
                }
            }
            .groupedRowSurface()

            // COPY BEGIN c8050b93 [NEEDS HUMAN REVIEW]
            if !invited.isEmpty {
                Section {
                    ForEach(invited) { person in
                        invitedRow(person)
                    }
                } header: {
                    Text("Invited, not yet in", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "Nobody here is in the room yet. Tap one that is still open to read the characters aloud again, to answer them, or to take the invitation back.",
                        bundle: .module)
                }
                .groupedRowSurface()
            }
            // COPY END c8050b93

            // COPY BEGIN 37fc6cfa [NEEDS HUMAN REVIEW]
            if let onInvite {
                Section {
                    Button(action: onInvite) {
                        Label {
                            Text("Invite someone", bundle: .module)
                        } icon: {
                            Image(systemName: "person.badge.plus")
                                .foregroundStyle(palette.accentColor)
                        }
                    }
                }
                .groupedRowSurface()
            }
            // COPY END 37fc6cfa
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(Text(verbatim: roomName))
        .toolbarTitleDisplayMode(.inline)
        // COPY BEGIN 18e78d15 [NEEDS HUMAN REVIEW]
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { dismiss() } label: { Text("Done", bundle: .module) }
            }
        }
        // COPY END 18e78d15
        .sheet(item: $removing) { member in
            RemoveMemberView(
                member: member,
                roomName: roomName,
                onRemove: { await onRemove?(member.id) }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .confirmingBlock($blocking) { person in await onBlock?(person) }
        .sheet(item: $rescinding) { person in
            RescindInvitationView(
                person: person, roomName: roomName,
                onRescind: { await onRescind?(person.id) }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(
            item: $checking,
            onDismiss: {
                rescinding = rescindingOnceChecked
                rescindingOnceChecked = nil
            }
        ) { person in
            InvitedPersonSheet(
                person: person,
                join: person.awaitsMyApproval && onDecide != nil ? joins.first { $0.id == person.id } : nil,
                onDecide: { join, admit in
                    checking = nil
                    Task { await onDecide?(join, admit) }
                },
                onRescind: onRescind.map { _ in
                    {
                        rescindingOnceChecked = person
                        checking = nil
                    }
                })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .navigationDestination(for: PersonRoute.self) { route in
            personPage?(route.person, actions(for: route.person))
        }
    }

    private func actions(for person: ParticipantID) -> PersonActions? {
        guard person != viewer, let member = members.first(where: { $0.id == person }),
            onRemove != nil || onBlock != nil
        else { return nil }
        return PersonActions(
            roomName: roomName,
            remove: onRemove.map { _ in { removing = member } },
            block: onBlock.map { _ in { blocking = member } })
    }

    @ViewBuilder
    private func row(_ member: Member) -> some View {
        if member.id == viewer {
            person(member)
        } else {
            person(member).contextMenu {
                // COPY BEGIN 6c95b4b6 [NEEDS HUMAN REVIEW]
                if onBlock != nil {
                    Button(role: .destructive) {
                        blocking = member
                    } label: {
                        Label {
                            Text("Block everywhere", bundle: .module)
                        } icon: {
                            Image(systemName: "hand.raised")
                        }
                    }
                    .tint(palette.destructive)
                }
                // COPY END 6c95b4b6

                // COPY BEGIN 3f84a555 [NEEDS HUMAN REVIEW]
                if onRemove != nil {
                    Button(role: .destructive) {
                        removing = member
                    } label: {
                        Label {
                            Text("Remove from room", bundle: .module)
                        } icon: {
                            Image(systemName: "person.slash")
                                .foregroundStyle(palette.destructive)
                        }
                    }
                    .tint(palette.destructive)
                }
                // COPY END 3f84a555
            }
        }
    }

    @ViewBuilder
    private func invitedRow(_ person: InvitedPerson) -> some View {
        if person.hasLapsed {
            lapsedRow(person)
        } else {
            liveInvitedRow(person)
        }
    }

    private func lapsedRow(_ person: InvitedPerson) -> some View {
        PersonRow(
            name: person.person.displayName,
            initials: person.person.initials,
            id: person.person.id,
            detail: waiting(person)
        )
    }

    @ViewBuilder
    private func liveInvitedRow(_ person: InvitedPerson) -> some View {
        Button {
            checking = person
        } label: {
            PersonRow(
                name: person.person.displayName,
                initials: person.person.initials,
                id: person.person.id,
                detail: waiting(person)
            )
        }
        .foregroundStyle(palette.primaryText)
        .contextMenu {
            // COPY BEGIN da937147 [NEEDS HUMAN REVIEW]
            Button {
                checking = person
            } label: {
                Label {
                    Text("Show the characters", bundle: .module)
                } icon: {
                    Image(systemName: "character.textbox")
                }
            }
            // COPY END da937147

            // COPY BEGIN b43a17c1 [NEEDS HUMAN REVIEW]
            if onRescind != nil {
                Button(role: .destructive) {
                    rescinding = person
                } label: {
                    Label {
                        Text("Take back the invitation", bundle: .module)
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
                .tint(palette.destructive)
            }
            // COPY END b43a17c1
        }
    }

    // COPY BEGIN 40c0b4a6 [NEEDS HUMAN REVIEW]
    private func waiting(_ person: InvitedPerson) -> Text {
        if person.hasConfirmed {
            if let agreed = person.agreed {
                return person.awaitsMyApproval
                    ? Text(
                        "Confirmed the characters — \(agreed.count) of \(agreed.needed) agreed, and you have not",
                        bundle: .module)
                    : Text(
                        "Confirmed the characters — \(agreed.count) of \(agreed.needed) agreed",
                        bundle: .module)
            }
            return person.awaitsMyApproval
                ? Text("Confirmed the characters — yours to let in", bundle: .module)
                : Text("Confirmed the characters — waiting to be let in", bundle: .module)
        }
        if person.hasLapsed, !person.isIndefinite {
            return Text(
                "Invited. Ran out \(person.expiresAt.formatted(.relative(presentation: .named))). Sending another is the way back.",
                bundle: .module)
        }
        if !person.isMine {
            return person.isIndefinite
                ? Text("Invited by \(person.invitedBy.displayName). Nothing back yet.", bundle: .module)
                : Text(
                    "Invited by \(person.invitedBy.displayName). Nothing back yet — runs out \(person.expiresAt.formatted(.relative(presentation: .named))).",
                    bundle: .module)
        }
        return person.isIndefinite
            ? Text("Invited. Nothing back yet.", bundle: .module)
            : Text(
                "Invited. Nothing back yet — runs out \(person.expiresAt.formatted(.relative(presentation: .named))).",
                bundle: .module)
    }
    // COPY END 40c0b4a6

    // COPY BEGIN 93c0f1a5 [NEEDS HUMAN REVIEW]
    private func person(_ member: Member) -> some View {
        NavigationLink(value: PersonRoute(member.id)) {
            PersonRow(
                name: member.displayName,
                initials: member.initials,
                id: member.id,
                detail: member.id == viewer ? Text("You", bundle: .module) : nil
            )
        }
    }
    // COPY END 93c0f1a5
}

struct RemoveMemberView: View {
    let member: Member
    let roomName: String
    let onRemove: () async -> Void

    // COPY BEGIN c52bb035 [NEEDS HUMAN REVIEW]
    var body: some View {
        MembershipDecisionSheet(
            question: Text("Remove \(member.displayName)?", bundle: .module),
            context: Text("from \(roomName)", bundle: .module),
            confirm: Text("Remove \(member.displayName)", bundle: .module),
            onConfirm: onRemove
        ) {
            MembershipFact(
                "key.horizontal",
                Text(
                    "Everyone still here gets a new key and \(member.displayName) does not, so they stop receiving anything from now on.",
                    bundle: .module))
            MembershipFact(
                "tray.full",
                Text(
                    "Nothing they already collected comes back. Every message they have is still theirs.",
                    bundle: .module))
            MembershipFact(
                "eye",
                Text(
                    "The room will say what happened. \(member.displayName) is told in their own copy, and nowhere else.",
                    bundle: .module))
        }
    }
    // COPY END c52bb035
}

struct RescindInvitationView: View {
    let person: InvitedPerson
    let roomName: String
    let onRescind: () async -> Void

    // COPY BEGIN 7cf63d28 [NEEDS HUMAN REVIEW]
    var body: some View {
        MembershipDecisionSheet(
            question: Text("Take back the invitation to \(person.person.displayName)?", bundle: .module),
            context: Text("for \(roomName)", bundle: .module),
            confirm: Text("Take it back", bundle: .module),
            onConfirm: onRescind
        ) {
            MembershipFact(
                "lock",
                Text(
                    "The room will not let anybody in on it, from now on. Nothing else about the room changes.",
                    bundle: .module))
            MembershipFact(
                "link",
                Text(
                    "\(person.person.displayName) may still be holding the link, and this cannot reach their device to stop it working there.",
                    bundle: .module))
            MembershipFact(
                "eye.slash",
                person.isMine
                    ? Text(
                        "They are not told. On their phone this looks the same as nobody getting round to it, and you can invite them again at any time.",
                        bundle: .module)
                    : Text(
                        "They are not told. On their phone this looks the same as nobody getting round to it.",
                        bundle: .module))
            if !person.isMine {
                MembershipFact(
                    "person.badge.clock",
                    Text(
                        "\(person.invitedBy.displayName) made this offer. The room will show that you took it back, and only they can send it again.",
                        bundle: .module))
            }
        }
    }
    // COPY END 7cf63d28
}

struct InvitedPersonSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let person: InvitedPerson
    let join: PendingJoin?
    let onDecide: (PendingJoin, Bool) -> Void
    let onRescind: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let join {
                        JoinCheckCard(join: join) { admit in onDecide(join, admit) }
                    } else {
                        VerificationPhrase(person.phrase)
                        // COPY BEGIN ce26d2f9 [NEEDS HUMAN REVIEW]
                        Text(
                            "These are the characters you and \(person.person.displayName) were both shown. If what they read to you does not match, somebody else may be holding the invitation: take it back.",
                            bundle: .module)
                        // COPY END ce26d2f9
                            .font(CarpenterFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let onRescind {
                        // COPY BEGIN 0973868b [NEEDS HUMAN REVIEW]
                        Button(role: .destructive, action: onRescind) {
                            Label {
                                Text("Take back the invitation", bundle: .module)
                            } icon: {
                                Image(systemName: "trash").foregroundStyle(palette.destructive)
                            }
                            .primaryAction()
                            .enabledLabelColor(palette.destructive)
                        }
                        .quietActionButton()
                        .tint(palette.destructive)
                        // COPY END 0973868b
                    }
                }
                .padding(.horizontal, CarpenterMetrics.screenMargin)
                .padding(.vertical, 16)
            }
            .background(palette.background)
            .navigationTitle(Text(verbatim: person.person.displayName))
            .toolbarTitleDisplayMode(.inline)
            // COPY BEGIN 3fa21cdd [NEEDS HUMAN REVIEW]
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
            // COPY END 3fa21cdd
        }
    }
}

#if DEBUG
    #Preview("Who is in this room") {
        NavigationStack {
            RoomMembersView(
                roomName: "Hangar 7",
                members: [
                    Member(id: ParticipantID(rawValue: Data([1])), displayName: "Ada"),
                    Member(id: ParticipantID(rawValue: Data([2])), displayName: "Bo"),
                    Member(id: ParticipantID(rawValue: Data([3])), displayName: "Nils"),
                ],
                viewer: ParticipantID(rawValue: Data([1])),
                onInvite: {}
            )
        }
        .themed(.default)
    }

    #Preview("Removing somebody") {
        RemoveMemberView(
            member: Member(id: ParticipantID(rawValue: Data([2])), displayName: "Bo"),
            roomName: "Hangar 7",
            onRemove: {}
        )
        .themed(.default)
    }
#endif
