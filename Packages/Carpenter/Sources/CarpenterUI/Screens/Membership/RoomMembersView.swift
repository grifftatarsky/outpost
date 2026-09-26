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
    private let onDecide: ((ParticipantID, Bool) async -> Void)?
    private let onBlock: ((ParticipantID) async -> Void)?

    @State private var removing: Member?
    @State private var blocking: Member?
    @State private var rescinding: InvitedPerson?
    @State private var showingPhrase: InvitedPerson?

    public init(
        roomName: String,
        members: [Member],
        invited: [InvitedPerson] = [],
        viewer: ParticipantID? = nil,
        onRemove: ((ParticipantID) async -> Void)? = nil,
        onInvite: (() -> Void)? = nil,
        onBlock: ((ParticipantID) async -> Void)? = nil,
        onRescind: ((ParticipantID) async -> Void)? = nil,
        onDecide: ((ParticipantID, Bool) async -> Void)? = nil
    ) {
        self.roomName = roomName
        self.members = members
        self.invited = invited
        self.viewer = viewer
        self.onRemove = onRemove
        self.onInvite = onInvite
        self.onBlock = onBlock
        self.onRescind = onRescind
        self.onDecide = onDecide
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
                            "Touch and hold somebody to remove them from this room, or to block them everywhere.",
                            bundle: .module)
                    case (true, false):
                        Text(
                            "Touch and hold somebody to remove them from this room.", bundle: .module)
                    case (false, true):
                        Text("Touch and hold somebody to block them everywhere.", bundle: .module)
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
                        "Nobody here is in the room yet. Touch and hold one that is still open to read the characters aloud again, or to take the invitation back.",
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
        .sheet(item: $showingPhrase) { person in
            VerificationPhraseSheet(
                name: person.person.displayName, phrase: person.phrase, confirmedAt: nil)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
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
        PersonRow(
            name: person.person.displayName,
            initials: person.person.initials,
            id: person.person.id,
            detail: waiting(person)
        )
        .contextMenu {
            // COPY BEGIN da937147 [NEEDS HUMAN REVIEW]
            Button {
                showingPhrase = person
            } label: {
                Label {
                    Text("Show the characters", bundle: .module)
                } icon: {
                    Image(systemName: "character.textbox")
                }
            }
            // COPY END da937147

            if person.awaitsMyApproval, let onDecide {
                // COPY BEGIN 072f923a [NEEDS HUMAN REVIEW]
                Button {
                    Task { await onDecide(person.id, true) }
                } label: {
                    Label {
                        Text("Let them in", bundle: .module)
                    } icon: {
                        Image(systemName: "person.badge.plus")
                    }
                }
                // COPY END 072f923a

                // COPY BEGIN ec57a2a6 [NEEDS HUMAN REVIEW]
                Button {
                    Task { await onDecide(person.id, false) }
                } label: {
                    Label {
                        Text("Do not let them in", bundle: .module)
                    } icon: {
                        Image(systemName: "hand.raised")
                    }
                }
                // COPY END ec57a2a6
            }

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
