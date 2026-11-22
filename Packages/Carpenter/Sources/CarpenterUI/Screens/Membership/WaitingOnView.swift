import CarpenterKit
import SwiftUI

public struct WaitingOnView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let roomName: String
    private let people: [WaitingOnPerson]

    public init(roomName: String, people: [WaitingOnPerson]) {
        self.roomName = roomName
        self.people = people
    }

    public var body: some View {
        List {
            Section {
                // COPY BEGIN f17c5271 [NEEDS HUMAN REVIEW]
                if people.isEmpty {
                    Text("There is nobody else in here to wait on.", bundle: .module)
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.secondaryText)
                }
                // COPY END f17c5271
                ForEach(people) { person in
                    PersonRow(
                        name: person.member.displayName,
                        initials: person.member.initials,
                        id: person.member.id,
                        detail: detail(person))
                        .accessibilityElement(children: .combine)
                }
            } footer: {
                // COPY BEGIN 0bcd12f2 [NEEDS HUMAN REVIEW]
                Text(
                    "Nothing here is a fault. A message reaches somebody when they next open the app, so waiting on somebody who hasn't opened it is normal. Last heard is the newest thing of theirs on this phone, with the time their device gave it.",
                    bundle: .module)
                // COPY END 0bcd12f2
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN a5491637 [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Waiting on", bundle: .module))
        .navigationSubtitle(Text(verbatim: roomName))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { dismiss() } label: { Text("Done", bundle: .module) }
            }
        }
        // COPY END a5491637
    }

    // COPY BEGIN aa5a62f8 [NEEDS HUMAN REVIEW]
    private func withTakenBack(_ person: WaitingOnPerson, after holding: Text) -> Text {
        guard person.takenBack > 0 else { return holding }
        return Text(
            "\(holding) Of those, ^[\(person.takenBack) message](inflect: true) went uncollected for ^[\(NotGone.takenBackAfterDays) day](inflect: true), so what was waiting was taken back from your iCloud.",
            bundle: .module)
    }
    // COPY END aa5a62f8

    private func detail(_ person: WaitingOnPerson) -> Text {
        var holding: Text
        // COPY BEGIN f8ad89a0 [NEEDS HUMAN REVIEW]
        switch person.holding {
        case .everything:
            holding = Text("Has everything you sent here.", bundle: .module)
        case .missing(let count):
            holding = Text(
                "Hasn't received ^[\(count) message](inflect: true) you sent here yet.",
                bundle: .module)
        case .notCheckedYet:
            holding = Text("Not checked since the app opened.", bundle: .module)
        }
        holding = withTakenBack(person, after: holding)
        guard let heard = person.lastHeard else {
            return Text("\(holding) Nothing heard from them yet.", bundle: .module)
        }
        return Text(
            "\(holding) Last heard \(heard.formatted(date: .abbreviated, time: .shortened)).",
            bundle: .module)
        // COPY END f8ad89a0
    }
}

#if DEBUG
    #Preview("Waiting on") {
        NavigationStack {
            WaitingOnView(
                roomName: "Hangar 7",
                people: [
                    WaitingOnPerson(member: Fixtures.camilla, holding: .missing(3), lastHeard: Fixtures.now),
                    WaitingOnPerson(member: Fixtures.cassilda, holding: .notCheckedYet, lastHeard: nil),
                ])
        }
        .themed(.default)
    }
#endif
