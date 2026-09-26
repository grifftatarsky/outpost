import CarpenterKit
import SwiftUI

public struct OutpostReviewSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.clock) private var clock
    @Environment(\.dismiss) private var dismiss

    private let review: OutpostReview
    private let onChoose: (ParticipantID, OutpostAccessChoice) async -> String?

    @State private var answers: [ParticipantID: OutpostAccessChoice] = [:]
    @State private var deciding: OutpostAccessSubject?
    @State private var problem: String?

    public init(
        review: OutpostReview,
        onChoose: @escaping (ParticipantID, OutpostAccessChoice) async -> String? = { _, _ in nil }
    ) {
        self.review = review
        self.onChoose = onChoose
    }

    public var body: some View {
        NavigationStack {
            List {
                // COPY BEGIN a7349ba2 [NEEDS HUMAN REVIEW]
                SettingsHeaderCard(
                    icon: "person.2.badge.key.fill",
                    title: Text("Who sees your Outpost", bundle: .module),
                    paragraph: Text(
                        "^[\(review.people.count + 1) member](inflect: true) in \(review.roomName). Anyone left with no access stays that way, and nothing you post reaches them.",
                        bundle: .module))
                // COPY END a7349ba2

                Section {
                    ForEach(review.people) { person in
                        PersonRow(
                            name: person.member.displayName, initials: person.member.initials,
                            id: person.member.id, detail: detail(for: person)
                        ) {
                            action(for: person)
                        }
                    }
                } footer: {
                    // COPY BEGIN 7ca2e27e [NEEDS HUMAN REVIEW]
                    Text(
                        "Giving someone access to everything hands them your whole Outpost history, including posts from before you met.",
                        bundle: .module)
                    // COPY END 7ca2e27e
                }
                .groupedRowSurface()
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            // COPY BEGIN 4ff868d9 [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("Who sees your Outpost", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
            // COPY END 4ff868d9
            .safeAreaInset(edge: .bottom) { blanketButtons }
            .outpostAccessSheet(deciding: $deciding) { person, choice in
                answer(person, choice)
                return nil
            }
            // COPY BEGIN 39cd5770 [NEEDS HUMAN REVIEW]
            .alert(
                Text("That did not go through", bundle: .module),
                isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
            ) {
                Button { problem = nil } label: { Text("OK", bundle: .module) }
            } message: {
                Text(verbatim: problem ?? "")
            }
            // COPY END 39cd5770
        }
    }

    @State private var allowingEveryone = false

    private var blanketButtons: some View {
        HStack(spacing: 10) {
            // COPY BEGIN 50b77893 [NEEDS HUMAN REVIEW]
            Button {
                allowingEveryone = true
            } label: {
                Text("Allow everyone", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            // COPY END 50b77893

            // COPY BEGIN 2fcccda8 [NEEDS HUMAN REVIEW]
            Button {
                for person in waiting { answer(person.id, .no) }
            } label: {
                Text("Allow nobody", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(palette.destructive)
            .foregroundStyle(palette.destructiveActionLabel)
        }
        .disabled(waiting.isEmpty)
        .alert(Text("This cannot be undone", bundle: .module), isPresented: $allowingEveryone) {
            Button(role: .destructive) {
                for person in waiting { answer(person.id, .everything) }
            } label: {
                Text("Let them all in", bundle: .module)
            }
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
        } message: {
            Text(
                "^[\(waiting.count) person](inflect: true) will be able to read your Outpost, including everything already on it. You cannot take back what they have.",
                bundle: .module)
        }
            // COPY END 2fcccda8
        .padding(.horizontal, CarpenterMetrics.screenMargin)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var waiting: [OutpostReview.Person] {
        review.undecided.filter { answers[$0.id] == nil }
    }

    private func subject(_ person: OutpostReview.Person) -> OutpostAccessSubject {
        var grant = person.grant
        if let answered = answers[person.id] {
            var made = grant ?? OutpostAccess.Grant(windows: [])
            switch answered {
            case .everything: made.windows = [AccessWindow()]
            case .fromNow: made.windows.append(AccessWindow(from: .now))
            case .no: made.windows = made.windows.filter { !$0.isOpen }
            }
            grant = made
        }
        return OutpostAccessSubject(person: person.member, grant: grant)
    }

    private func answer(_ person: ParticipantID, _ choice: OutpostAccessChoice) {
        answers[person] = choice
        Task {
            if let failure = await onChoose(person, choice) {
                answers[person] = nil
                problem = failure
            }
        }
    }

    // COPY BEGIN a227a250 [NEEDS HUMAN REVIEW]
    private func detail(for person: OutpostReview.Person) -> Text {
        if let answered = answers[person.id] {
            switch answered {
            case .everything: return Text("Everything, chosen here", bundle: .module)
            case .fromNow: return Text("Posts from today, chosen here", bundle: .module)
            case .no: return Text("No access, chosen here", bundle: .module)
            }
        }
        guard let grant = person.grant else { return Text("No access", bundle: .module) }
        guard grant.isAllowed else { return refused(person) }
        guard let from = grant.from else { return everything(person) }
        return fromDate(from, person)
    }
    // COPY END a227a250

    // COPY BEGIN 4daacf08 [NEEDS HUMAN REVIEW]
    private func refused(_ person: OutpostReview.Person) -> Text {
        guard let decidedIn = person.decidedIn else { return Text("No access", bundle: .module) }
        return Text("No access, from \(decidedIn)", bundle: .module)
    }
    // COPY END 4daacf08

    // COPY BEGIN 13320d36 [NEEDS HUMAN REVIEW]
    private func everything(_ person: OutpostReview.Person) -> Text {
        guard let decidedIn = person.decidedIn else { return Text("Everything", bundle: .module) }
        return Text("Everything, from \(decidedIn)", bundle: .module)
    }
    // COPY END 13320d36

    // COPY BEGIN dd3d0815 [NEEDS HUMAN REVIEW]
    private func fromDate(_ from: Date, _ person: OutpostReview.Person) -> Text {
        let when = Calendar.current.isDate(from, inSameDayAs: clock.now)
            ? String(localized: "today", bundle: .module, comment: "Access began earlier today")
            : from.formatted(date: .abbreviated, time: .omitted)
        guard let decidedIn = person.decidedIn else {
            return Text("Posts from \(when)", bundle: .module)
        }
        return Text("Posts from \(when), from \(decidedIn)", bundle: .module)
    }
    // COPY END dd3d0815

    // COPY BEGIN 067ba448 [NEEDS HUMAN REVIEW]
    @ViewBuilder private func action(for person: OutpostReview.Person) -> some View {
        if answers[person.id] != nil {
            Button { deciding = subject(person) } label: { Text("Change", bundle: .module) }
                .buttonStyle(.borderless)
        } else if person.isUndecided {
            Button { deciding = subject(person) } label: { Text("Choose", bundle: .module) }
                .buttonStyle(.borderless)
        } else {
            Text("Already set", bundle: .module)
                .font(CarpenterFont.rowDetail)
                .foregroundStyle(palette.quaternaryText)
        }
    }
    // COPY END 067ba448
}

#if DEBUG
    #Preview("60 Access review, sheet") {
        OutpostReviewSheet(
            review: OutpostReview(
                room: RoomID(),
                roomName: "Zeppelin Enthusiasts",
                people: [
                    OutpostReview.Person(member: Fixtures.hastur, grant: nil),
                    OutpostReview.Person(
                        member: Fixtures.camilla, grant: OutpostAccess.Grant(),
                        decidedIn: "The Gazette"),
                    OutpostReview.Person(member: Fixtures.cassilda, grant: nil),
                ]))
            .themed(.default)
    }
#endif
