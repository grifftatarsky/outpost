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
                if isOffered {
                    Text(
                        "You and \(name) have never compared codes. It takes a minute, and you only need to do it once.",
                        bundle: .module
                    )
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                }

                Text(
                    "Both devices show these same two halves. Read yours to \(name) and listen to theirs: each should match what the other person reads. If somebody had put themselves in the middle, one half would be different.",
                    bundle: .module
                )
                .font(CarpenterFont.rowDetail)
                .foregroundStyle(palette.secondaryText)

                ForEach(person.comparison) { half in
                    VStack(alignment: .leading, spacing: 8) {
                        (half.isViewer ? Text("Yours", bundle: .module) : Text(verbatim: half.name))
                            .sectionHeading()
                            .foregroundStyle(palette.tertiaryText)
                        VerificationPhrase(half.half)
                            .frame(maxWidth: .infinity)
                    }
                }

                outcome
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.vertical, 20)
        }
        .background(palette.background)
        .navigationTitle(Text("Compare codes", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
    }

    private var name: String { person.person.displayName }

    @ViewBuilder
    private var outcome: some View {
        if markedNow {
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

                Button {
                    saidTheyDiffer = true
                } label: {
                    Text("They don't match", bundle: .module).primaryAction()
                }
                .quietActionButton()
            }

            if saidTheyDiffer {
                note(
                    Text(
                        "Check that you are both looking at each other, not at somebody else in the room. If you are, somebody may be in the middle: say nothing here you would not say in front of a stranger, and compare again in person. Nothing was sent to anybody.",
                        bundle: .module))
            }
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
    public let room: ConversationID
    public let people: [VerifiedPerson]

    public var id: ConversationID { room }

    public init(room: ConversationID, people: [VerifiedPerson]) {
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
                            Text(
                                "You have never compared codes with these people. Each takes a minute, and you only need to do it once. This is offered once; you can always compare from Who you are talking to.",
                                bundle: .module)
                        }
                        .groupedRowSurface()
                    }
                    .scrollContentBackground(.hidden)
                    .background(palette.background)
                    .navigationTitle(Text("Compare codes", bundle: .module))
                    .toolbarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Not now", bundle: .module) }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }
}
