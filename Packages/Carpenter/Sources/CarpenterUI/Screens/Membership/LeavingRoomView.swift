import CarpenterKit
import SwiftUI

/// The Outpost-access step of leaving a room.
///
/// Leaving a room used to end the room and nothing else, so anybody this member let into their
/// Outpost *because of* that room kept the access after the reason for it was gone. This is the
/// stop-at-today question, asked once, on the way out.
///
/// It is a sheet rather than more buttons on the confirmation dialog because it is a scoped task
/// closely related to the current context, which is what Apple names a sheet for, and because an
/// action sheet holds no more than four buttons including Cancel.
public struct LeavingRoomView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let roomName: String
    private let people: [Member]
    private let onLeave: ([ParticipantID]) async -> Void

    @State private var stopping: Set<ParticipantID>

    public init(
        roomName: String, people: [Member],
        onLeave: @escaping ([ParticipantID]) async -> Void
    ) {
        self.roomName = roomName
        self.people = people
        self.onLeave = onLeave
        // Stopping is the answer somebody reached this screen to give, so it starts chosen for
        // everybody. Nothing happens until they confirm, and each row can be turned back off.
        _stopping = State(initialValue: Set(people.map(\.id)))
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(people) { person in
                        ChoiceRow(
                            title: Text(verbatim: person.displayName),
                            isSelected: stopping.contains(person.id),
                            action: { toggle(person.id) })
                    }
                } header: {
                    // COPY BEGIN a311e102 [NEEDS HUMAN REVIEW]
                    Text("Stop showing your Outpost to", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "You let these people read your Outpost when you were in \(roomName). Stopping keeps what they have already seen — it ends what they see from today.",
                        bundle: .module)
                    // COPY END a311e102
                }
                .groupedRowSurface()
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            // COPY BEGIN 35542f83 [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("Leaving \(roomName)", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let chosen = Array(stopping)
                        dismiss()
                        Task { await onLeave(chosen) }
                    } label: {
                        Text("Leave", bundle: .module)
                    }
                    .tint(palette.destructive)
                }
            // COPY END 35542f83
            }
        }
    }

    private func toggle(_ person: ParticipantID) {
        if stopping.contains(person) {
            stopping.remove(person)
        } else {
            stopping.insert(person)
        }
    }
}

#Preview("Leaving a room with Outpost readers") {
    LeavingRoomView(
        roomName: "Lanterns",
        people: [
            Member(id: ParticipantID(rawValue: Data([1])), displayName: "Aurelia"),
            Member(id: ParticipantID(rawValue: Data([2])), displayName: "Bramwell"),
        ],
        onLeave: { _ in }
    )
    .themed(.default)
}
