import CarpenterKit
import SwiftUI

public struct BlockedPeopleView: View {
    @Environment(\.palette) private var palette

    private let people: [Member]
    private let onUnblock: (ParticipantID) async -> Void

    public init(people: [Member], onUnblock: @escaping (ParticipantID) async -> Void) {
        self.people = people
        self.onUnblock = onUnblock
    }

    public var body: some View {
        List {
            if people.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("Nobody is blocked", bundle: .module)
                    } icon: {
                        Image(systemName: "hand.raised")
                    }
                } description: {
                    Text(
                        "Hold a message and choose Block to stop seeing anything that person sends.",
                        bundle: .module)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(people) { person in
                        PersonRow(name: person.displayName, initials: person.initials, id: person.id)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    Task { await onUnblock(person.id) }
                                } label: {
                                    Label {
                                        Text("Unblock", bundle: .module)
                                    } icon: {
                                        Image(systemName: "hand.raised.slash")
                                    }
                                }
                                .tint(palette.accentColor)
                            }
                    }
                } footer: {
                    Text(
                        "Swipe to unblock. Everything they sent while blocked is still here and appears when you do — it was kept, not read.",
                        bundle: .module)
                }
                .groupedRowSurface()
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(Text("Blocked people", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
    }
}

public struct LeavingThisRoom: Sendable {
    public let leave: @MainActor @Sendable () async -> Void

    public init(leave: @escaping @MainActor @Sendable () async -> Void) {
        self.leave = leave
    }
}

extension EnvironmentValues {
    @Entry public var leavingThisRoom: LeavingThisRoom?
}

struct ConfirmingBlock: ViewModifier {
    @Environment(\.leavingThisRoom) private var leaving

    @Binding var member: Member?
    let onBlock: (ParticipantID) async -> Void

    private var isAsking: Binding<Bool> {
        Binding(get: { member != nil }, set: { if !$0 { member = nil } })
    }

    private func message(_ person: Member) -> Text {
        Text(
            "You stop seeing anything \(person.displayName) sends, in every room, on all your devices. They are not told, and nothing is erased. You can undo this under You › Safety.",
            bundle: .module)
    }

    func body(content: Content) -> some View {
        if let leaving {
            content.confirmationDialog(
                Text("Block this person?", bundle: .module), isPresented: isAsking,
                titleVisibility: .visible, presenting: member
            ) { person in
                Button(role: .destructive) {
                    Task { await onBlock(person.id) }
                } label: {
                    Text("Block", bundle: .module)
                }
                Button(role: .destructive) {
                    Task {
                        await onBlock(person.id)
                        await leaving.leave()
                    }
                } label: {
                    Text("Block and Leave", bundle: .module)
                }
                Button(role: .cancel) {
                } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: { person in
                message(person)
            }
        } else {
            content.alert(
                Text("Block this person?", bundle: .module), isPresented: isAsking, presenting: member
            ) { person in
                Button(role: .destructive) {
                    Task { await onBlock(person.id) }
                } label: {
                    Text("Block", bundle: .module)
                }
                Button(role: .cancel) {
                } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: { person in
                message(person)
            }
        }
    }
}

extension View {
    public func confirmingBlock(
        _ member: Binding<Member?>, onBlock: @escaping (ParticipantID) async -> Void
    ) -> some View {
        modifier(ConfirmingBlock(member: member, onBlock: onBlock))
    }
}

#if DEBUG
    #Preview("Blocked people") {
        NavigationStack {
            BlockedPeopleView(people: [Fixtures.hastur, Fixtures.yhtill], onUnblock: { _ in })
        }
        .themed(.default)
    }

    #Preview("Blocked people — nobody") {
        NavigationStack {
            BlockedPeopleView(people: [], onUnblock: { _ in })
        }
        .themed(.default)
    }
#endif
