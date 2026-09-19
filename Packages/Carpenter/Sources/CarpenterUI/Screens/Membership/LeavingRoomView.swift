import CarpenterKit
import SwiftUI

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
        _stopping = State(initialValue: Set(people.map(\.id)))
    }

    public var body: some View {
        NavigationStack {
            SettingsPage {
                Section {
                    ForEach(people) { person in
                        ChoiceRow(
                            title: Text(verbatim: person.displayName),
                            isSelected: stopping.contains(person.id),
                            action: { toggle(person.id) })
                    }
                } header: {
                    Text("Stop showing your Outpost to", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "You let these people read your Outpost when you were in \(roomName). Stopping keeps what they have already seen — it ends what they see from today.",
                        bundle: .module)
                }
                .groupedRowSurface()
            }
            .listSurfaceHidden()
            .pageBackground()
            .navigationTitle(Text("Leaving \(roomName)", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                        .keyboardShortcut(.cancelAction)
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
