import CarpenterKit
import SwiftUI

public struct ComparisonHalf: Identifiable, Hashable, Sendable {
    public let name: String
    public let half: String
    public let isViewer: Bool

    public var id: String { half + name }

    public init(name: String, half: String, isViewer: Bool) {
        self.name = name
        self.half = half
        self.isViewer = isViewer
    }
}

public struct VerifiedPerson: Identifiable, Hashable, Sendable {
    public let person: Member
    public let phrase: String?
    public let confirmedAt: Date?
    public let isViewer: Bool
    public let isFounder: Bool
    public let comparison: [ComparisonHalf]
    public let checkedAt: Date?
    public let devicesAddedSince: [Date]

    public var id: ParticipantID { person.id }

    public init(
        person: Member, phrase: String?, confirmedAt: Date?, isViewer: Bool = false,
        isFounder: Bool = false, comparison: [ComparisonHalf] = [], checkedAt: Date? = nil,
        devicesAddedSince: [Date] = []
    ) {
        self.person = person
        self.phrase = phrase
        self.confirmedAt = confirmedAt
        self.isViewer = isViewer
        self.isFounder = isFounder
        self.comparison = comparison
        self.checkedAt = checkedAt
        self.devicesAddedSince = devicesAddedSince
    }
}

public struct WhoYouAreTalkingToView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let roomName: String
    private let people: [VerifiedPerson]
    private let onMarkChecked: ((ParticipantID) async -> Void)?

    public init(
        roomName: String, people: [VerifiedPerson],
        onMarkChecked: ((ParticipantID) async -> Void)? = nil
    ) {
        self.roomName = roomName
        self.people = people
        self.onMarkChecked = onMarkChecked
    }

    public var body: some View {
        List {
            Section {
                ForEach(people) { person in
                    row(person)
                }
            } footer: {
                Text(
                    "The characters under a name are the ones read aloud when that person was invited. Open anybody to compare codes with them, whenever you like — including people you never met through an invitation.",
                    bundle: .module)
            }
            .groupedRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(Text("Who you are talking to", bundle: .module))
        .navigationSubtitle(Text(verbatim: roomName))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { dismiss() } label: { Text("Done", bundle: .module) }
            }
        }
    }

    @ViewBuilder
    private func row(_ person: VerifiedPerson) -> some View {
        if person.isViewer || person.comparison.isEmpty {
            label(person)
        } else {
            NavigationLink {
                CompareCodesView(person: person, onMarkChecked: onMarkChecked)
            } label: {
                label(person)
            }
        }
    }

    @ViewBuilder
    private func label(_ person: VerifiedPerson) -> some View {
        if let phrase = person.phrase {
            PersonRow(
                name: person.person.displayName,
                initials: person.person.initials,
                id: person.person.id,
                detail: detail(person)
            ) {
                VerificationPhrase(phrase, size: .inline)
            }
        } else {
            PersonRow(
                name: person.person.displayName,
                initials: person.person.initials,
                id: person.person.id,
                detail: detail(person))
        }
    }

    private func detail(_ person: VerifiedPerson) -> Text {
        guard let checkedAt = person.checkedAt else { return joined(person) }
        return Text(
            "\(joined(person)) · codes checked \(checkedAt.formatted(date: .abbreviated, time: .omitted))",
            bundle: .module)
    }

    private func joined(_ person: VerifiedPerson) -> Text {
        if person.isFounder {
            return person.isViewer
                ? Text("You started this room", bundle: .module)
                : Text("Started this room", bundle: .module)
        }
        guard let confirmedAt = person.confirmedAt else {
            return person.phrase == nil
                ? Text("This room has no record of how they got in", bundle: .module)
                : Text("Invited, before this room kept a record of the check", bundle: .module)
        }
        return Text(
            "Characters confirmed \(confirmedAt.formatted(date: .abbreviated, time: .omitted))",
            bundle: .module)
    }
}

public struct VerificationPhraseSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let name: String
    private let phrase: String
    private let confirmedAt: Date?

    public init(name: String, phrase: String, confirmedAt: Date?) {
        self.name = name
        self.phrase = phrase
        self.confirmedAt = confirmedAt
    }

    public var body: some View {
        VStack(spacing: 20) {
            VerificationPhrase(phrase)

            if let confirmedAt {
                Text(
                    "This room recorded their confirmation on \(confirmedAt.formatted(date: .abbreviated, time: .shortened)).",
                    bundle: .module)
                    .font(CarpenterFont.caption)
                    .foregroundStyle(palette.tertiaryText)
                    .multilineTextAlignment(.center)
            }

            Text(
                "These are the characters you and \(name) have. If they do not match what they read out, somebody may have been in the middle when you met — stop, and start again in person.",
                bundle: .module)
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module).primaryAction()
            }
            .prominentActionButton()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.background)
    }
}

#if DEBUG
    #Preview("Who you are talking to") {
        NavigationStack {
            WhoYouAreTalkingToView(
                roomName: "Hangar 7",
                people: [
                    VerifiedPerson(
                        person: Member(id: ParticipantID(rawValue: Data([1])), displayName: "Ada"),
                        phrase: nil, confirmedAt: nil, isViewer: true, isFounder: true),
                    VerifiedPerson(
                        person: Member(id: ParticipantID(rawValue: Data([2])), displayName: "Bo"),
                        phrase: "K7M2QX", confirmedAt: .now.addingTimeInterval(-86_400)),
                ])
        }
        .themed(.default)
    }

    #Preview("The code") {
        VerificationPhraseSheet(
            name: "Bo", phrase: "K7M2QX", confirmedAt: .now.addingTimeInterval(-86_400))
            .themed(.default)
    }
#endif
