import CarpenterKit
import SwiftUI

public struct AddSomeoneView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verificationPhrase) private var phraseLookup

    private let rooms: () -> [RoomSummary]
    private let code: String
    private let onAdd: (RoomID, String) async -> Invite?
    private let onCreateRoom: (String, RoomAccess, Set<ParticipantID>) async -> Void
    private let preferences: RoomsListPreferences
    private let connections: [Connection]

    @State private var issued: PresentedInvite?
    @State private var working: RoomID?
    @State private var problem: String?
    @State private var naming = false

    public init(
        rooms: @escaping () -> [RoomSummary],
        code: String,
        onAdd: @escaping (RoomID, String) async -> Invite?,
        preferences: RoomsListPreferences,
        connections: [Connection] = [],
        onCreateRoom: @escaping (String, RoomAccess, Set<ParticipantID>) async -> Void = { _, _, _ in }
    ) {
        self.rooms = rooms
        self.code = code
        self.onAdd = onAdd
        self.preferences = preferences
        self.connections = connections
        self.onCreateRoom = onCreateRoom
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rooms()) { room in
                        Button {
                            add(to: room)
                        } label: {
                            row(room)
                        }
                        .buttonStyle(.plain)
                        .disabled(working != nil)
                    }
                } header: {
                    // COPY BEGIN f915f58f [NEEDS HUMAN REVIEW]
                    Text("Add them to", bundle: .module)
                } footer: {
                    if let problem {
                        Text(problem)
                            .foregroundStyle(palette.destructive)
                    } else {
                        Text(
                            "They are not in until they accept the invite you send back.",
                            bundle: .module)
                    }
                    // COPY END f915f58f
                }

                // COPY BEGIN 2977169c [NEEDS HUMAN REVIEW]
                Section {
                    Button {
                        naming = true
                    } label: {
                        Label {
                            Text("Start a new room for them", bundle: .module)
                        } icon: {
                            Image(systemName: "plus.circle")
                        }
                    }
                    .disabled(working != nil)
                }
                // COPY END 2977169c
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            // COPY BEGIN dd19f949 [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("Somebody sent their code", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
            }
            // COPY END dd19f949
            .sheet(item: $issued) { presented in
                InviteView(
                    roomName: presented.roomName, invite: presented.invite,
                    phrase: phraseLookup(presented.invite))
            }
            .sheet(isPresented: $naming) {
                NewRoomView(preferences: preferences, connections: connections) {
                    name, access, people in
                    await onCreateRoom(name, access, people)
                }
            }
        }
    }

    private func row(_ room: RoomSummary) -> some View {
        HStack(spacing: 12) {
            AvatarView(initials: room.initials, diameter: CarpenterMetrics.messageAvatar)
            // COPY BEGIN 142c43fd [NEEDS HUMAN REVIEW]
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                Text("^[\(room.memberCount) member](inflect: true)", bundle: .module)
                    .font(CarpenterFont.rowDetail)
                    .foregroundStyle(palette.tertiaryText)
            }
            // COPY END 142c43fd
            Spacer()
            if working == room.id {
                ProgressView()
            }
        }
        .contentShape(.rect)
    }

    // COPY BEGIN 87a8718f [NEEDS HUMAN REVIEW]
    private func add(to room: RoomSummary) {
        working = room.id
        problem = nil
        Task {
            defer { working = nil }
            guard let invite = await onAdd(room.id, code) else {
                problem = String(
                    localized: "That code could not be turned into an invite.", bundle: .module)
                return
            }
            issued = PresentedInvite(roomName: room.name, invite: invite)
        }
    }
    // COPY END 87a8718f
}

#if DEBUG
    #Preview("Somebody sent their code") {
        AddSomeoneView(
            rooms: { [Fixtures.zeppelinEnthusiasts] },
            code: "",
            onAdd: { _, _ in nil },
            preferences: RoomsListPreferences()
        )
        .themed(.default)
    }
#endif
