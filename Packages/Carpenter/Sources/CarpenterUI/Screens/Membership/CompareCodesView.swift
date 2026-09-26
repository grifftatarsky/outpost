import CarpenterKit
import SwiftUI

public struct CompareCodesView: View {
    @Environment(\.palette) private var palette

    private let person: VerifiedPerson
    private let isOffered: Bool
    private let onMarkChecked: ((ParticipantID) async -> Void)?

    @State private var markedNow = false
    @State private var saidTheyDiffer = false

    public init(
        person: VerifiedPerson, isOffered: Bool = false,
        onMarkChecked: ((ParticipantID) async -> Void)?
    ) {
        self.person = person
        self.isOffered = isOffered
        self.onMarkChecked = onMarkChecked
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // COPY BEGIN f98c28b4 [NEEDS HUMAN REVIEW]
                if isOffered {
                    Text(
                        "You and \(name) have never compared codes. It takes a minute, and you only need to do it once.",
                        bundle: .module
                    )
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                }
                // COPY END f98c28b4

                // COPY BEGIN 8644f0bb [NEEDS HUMAN REVIEW]
                Text(
                    "Both phones show these same two halves. Read yours to \(name) and listen to theirs: each should match what the other person reads. If somebody had put themselves in the middle, one half would be different.",
                    bundle: .module
                )
                .font(CarpenterFont.rowDetail)
                .foregroundStyle(palette.secondaryText)
                // COPY END 8644f0bb

                // COPY BEGIN 306e5f81 [NEEDS HUMAN REVIEW]
                ForEach(person.comparison) { half in
                    VStack(alignment: .leading, spacing: 8) {
                        (half.isViewer ? Text("Yours", bundle: .module) : Text(verbatim: half.name))
                            .sectionHeading()
                            .foregroundStyle(palette.tertiaryText)
                        VerificationPhrase(half.half)
                            .frame(maxWidth: .infinity)
                    }
                }
                // COPY END 306e5f81

                outcome
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.vertical, 20)
        }
        .background(palette.background)
        // COPY BEGIN 6a13e1df [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Compare codes", bundle: .module))
        // COPY END 6a13e1df
        .toolbarTitleDisplayMode(.inline)
    }

    private var name: String { person.person.displayName }

    @ViewBuilder
    private var outcome: some View {
        if markedNow {
            // COPY BEGIN 6dcf49b5 [NEEDS HUMAN REVIEW]
            note(Text("You marked these as matching just now. That is a note to yourself; nobody else is told.", bundle: .module))
        } else if let checkedAt = person.checkedAt {
            VStack(alignment: .leading, spacing: 8) {
                note(
                    Text(
                        "You marked these as matching on \(checkedAt.formatted(date: .abbreviated, time: .shortened)). That is a note to yourself; nobody else is told.",
                        bundle: .module))
                if person.devicesAddedSince.isEmpty {
                    note(Text("Since then, \(name) has not added a device.", bundle: .module))
                } else {
                    note(
                        Text(
                            "Since then, \(name) added ^[\(person.devicesAddedSince.count) device](inflect: true), most recently on \((person.devicesAddedSince.last ?? checkedAt).formatted(date: .abbreviated, time: .shortened)). A new device can read what they can.",
                            bundle: .module))
                }
            }
        } else if let onMarkChecked {
            VStack(spacing: 10) {
                Button {
                    Task {
                        await onMarkChecked(person.id)
                        markedNow = true
                    }
                } label: {
                    Text("They match", bundle: .module).primaryAction()
                }
                .prominentActionButton()
            // COPY END 6dcf49b5

                // COPY BEGIN 4faeda81 [NEEDS HUMAN REVIEW]
                Button {
                    saidTheyDiffer = true
                } label: {
                    Text("They don't match", bundle: .module).primaryAction()
                }
                .quietActionButton()
                // COPY END 4faeda81
            }

            // COPY BEGIN ecdfae7b [NEEDS HUMAN REVIEW]
            if saidTheyDiffer {
                note(
                    Text(
                        "Check that you are both looking at each other, not at somebody else in the room. If you are, somebody may be in the middle: say nothing here you would not say in front of a stranger, and compare again in person. Nothing was sent to anybody.",
                        bundle: .module))
            }
            // COPY END ecdfae7b
        }
    }

    private func note(_ text: Text) -> some View {
        text
            .font(CarpenterFont.footnote)
            .foregroundStyle(palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

public struct ComparisonOffer: Identifiable, Hashable, Sendable {
    public let room: RoomID
    public let people: [VerifiedPerson]

    public var id: RoomID { room }

    public init(room: RoomID, people: [VerifiedPerson]) {
        self.room = room
        self.people = people
    }
}

public struct ComparisonOfferView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let offer: ComparisonOffer
    private let onMarkChecked: (ParticipantID) async -> Void

    public init(offer: ComparisonOffer, onMarkChecked: @escaping (ParticipantID) async -> Void) {
        self.offer = offer
        self.onMarkChecked = onMarkChecked
    }

    public var body: some View {
        NavigationStack {
            Group {
                if offer.people.count == 1, let only = offer.people.first {
                    CompareCodesView(person: only, isOffered: true, onMarkChecked: onMarkChecked)
                } else {
                    List {
                        Section {
                            ForEach(offer.people) { person in
                                NavigationLink {
                                    CompareCodesView(
                                        person: person, isOffered: true, onMarkChecked: onMarkChecked)
                                } label: {
                                    PersonRow(
                                        name: person.person.displayName,
                                        initials: person.person.initials,
                                        id: person.person.id)
                                }
                            }
                        } footer: {
                            // COPY BEGIN 5a8e0221 [NEEDS HUMAN REVIEW]
                            Text(
                                "You have never compared codes with these people. Each takes a minute, and you only need to do it once. This is offered once; you can always compare from Who you are talking to.",
                                bundle: .module)
                            // COPY END 5a8e0221
                        }
                        .groupedRowSurface()
                    }
                    .scrollContentBackground(.hidden)
                    .background(palette.background)
                    // COPY BEGIN 480009a0 [NEEDS HUMAN REVIEW]
                    .navigationTitle(Text("Compare codes", bundle: .module))
                    // COPY END 480009a0
                    .toolbarTitleDisplayMode(.inline)
                }
            }
            // COPY BEGIN aa70704f [NEEDS HUMAN REVIEW]
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Not now", bundle: .module) }
                }
            }
            // COPY END aa70704f
        }
    }
}
